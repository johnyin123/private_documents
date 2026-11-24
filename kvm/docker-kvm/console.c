#define _GNU_SOURCE
#include <libvirt/libvirt.h>
#include <libvirt/virterror.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>
#include <limits.h>
#define SOCKET_BACKLOG 8
#define BUFFER_SIZE    4096
#define VM_WAIT_SEC    10
#define CLIENT_TIMEOUT 1200
#define CTRL_Q 0x11
static volatile sig_atomic_t g_running = 1;
#define LOG(fmt, ...) \
    fprintf(stderr, "[console] " fmt "\n", ##__VA_ARGS__)
struct console_ctx {
    virConnectPtr conn;
    virDomainPtr domain;
    virStreamPtr stream;
    int server_fd;
    int client_fd;
    char uuid[VIR_UUID_STRING_BUFLEN];
    char socket_path[sizeof(((struct sockaddr_un *)0)->sun_path)];
    pthread_t reader_thread;
    int reader_started;
};
static void signal_handler(int signo) {
    (void)signo;
    g_running = 0;
}
static int set_socket_timeout(int fd, int seconds) {
    struct timeval tv = { .tv_sec = seconds, .tv_usec = 0 };
    return setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
}
static int create_unix_server(const char *path) {
    int fd = -1;
    struct sockaddr_un addr;
    fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (fd < 0)
        return -1;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    if (strlen(path) >= sizeof(addr.sun_path)) {
        errno = ENAMETOOLONG;
        goto error;
    }
    snprintf(addr.sun_path, sizeof(addr.sun_path), "%s", path);
    /*
     * Do not blindly unlink an existing socket:
     * another server may already own it.
     */
    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0)
        goto error;
    if (chmod(path, 0600) < 0)
        goto error;
    if (listen(fd, SOCKET_BACKLOG) < 0)
        goto error;
    return fd;
error:
    {
        int saved_errno = errno;
        close(fd);
        errno = saved_errno;
        return -1;
    }
}
/* ---------------------------------------------------------- */
/* VM state                                                   */
/* ---------------------------------------------------------- */
static int guest_is_running(struct console_ctx *ctx)
{
    int state = 0;
    int reason = 0;
    if (virDomainGetState(ctx->domain, &state, &reason, 0) < 0)
        return 0;
    return state == VIR_DOMAIN_RUNNING ||
           state == VIR_DOMAIN_PAUSED;
}
static int wait_for_guest(struct console_ctx *ctx)
{
    for (int i = 0; i < VM_WAIT_SEC && g_running; i++) {
        if (guest_is_running(ctx))
            return 0;
        LOG("Waiting for VM %s ...", ctx->uuid);
        sleep(1);
    }
    return -1;
}
/* ---------------------------------------------------------- */
/* Client output                                              */
/* ---------------------------------------------------------- */
static int send_all(int fd, const void *buf, size_t len)
{
    const char *p = buf;
    while (len > 0) {
        ssize_t n = send(fd, p, len, MSG_NOSIGNAL);
        if (n < 0) {
            if (errno == EINTR)
                continue;
            return -1;
        }
        if (n == 0)
            return -1;
        p += n;
        len -= (size_t)n;
    }
    return 0;
}
/* ---------------------------------------------------------- */
/* Libvirt -> client                                          */
/* ---------------------------------------------------------- */
static void *console_reader(void *opaque)
{
    struct console_ctx *ctx = opaque;
    char buffer[BUFFER_SIZE];
    while (g_running) {
        int n = virStreamRecv(ctx->stream, buffer, sizeof(buffer));
        if (n < 0) {
            LOG("Console receive failed: %s",
                virGetLastError() ?
                virGetLastError()->message : "unknown error");
            break;
        }
        if (n == 0) {
            LOG("Console stream closed");
            break;
        }
        if (send_all(ctx->client_fd, buffer, (size_t)n) < 0) {
            LOG("Client disconnected");
            break;
        }
    }
    shutdown(ctx->client_fd, SHUT_RDWR);
    return NULL;
}
/* ---------------------------------------------------------- */
/* Client -> libvirt                                          */
/* ---------------------------------------------------------- */
static int console_writer(struct console_ctx *ctx)
{
    char buffer[BUFFER_SIZE];
    while (g_running) {
        struct pollfd pfd = {
            .fd = ctx->client_fd,
            .events = POLLIN
        };
        int ret = poll(&pfd, 1, 1000);
        if (ret < 0) {
            if (errno == EINTR)
                continue;
            LOG("Client poll failed: %s", strerror(errno));
            break;
        }
        if (ret == 0) {
            if (!guest_is_running(ctx)) {
                LOG("Guest stopped");
                break;
            }
            continue;
        }
        if (pfd.revents & (POLLERR | POLLHUP | POLLNVAL))
            break;
        if (!(pfd.revents & POLLIN))
            continue;
        ssize_t n = recv(ctx->client_fd, buffer, sizeof(buffer), 0);
        if (n < 0) {
            if (errno == EINTR || errno == EAGAIN ||
                errno == EWOULDBLOCK)
                continue;
            LOG("Client receive failed: %s", strerror(errno));
            break;
        }
        if (n == 0)
            break;
        /* Ctrl-Q disconnect */
        if (n == 1 && (unsigned char)buffer[0] == CTRL_Q)
            break;
        size_t offset = 0;
        while (offset < (size_t)n) {
            int sent = virStreamSend(
                ctx->stream,
                buffer + offset,
                (size_t)n - offset
            );
            if (sent <= 0) {
                LOG("Console send failed");
                return -1;
            }
            offset += (size_t)sent;
        }
    }
    return 0;
}
/* ---------------------------------------------------------- */
/* Console session                                            */
/* ---------------------------------------------------------- */
static int console_session(struct console_ctx *ctx)
{
    ctx->client_fd = accept4(
        ctx->server_fd, NULL, NULL, SOCK_CLOEXEC
    );
    if (ctx->client_fd < 0) {
        LOG("Accept failed: %s", strerror(errno));
        return -1;
    }
    LOG("Client connected to VM %s", ctx->uuid);
    set_socket_timeout(ctx->client_fd, CLIENT_TIMEOUT);
    ctx->stream = virStreamNew(ctx->conn, 0);
    if (!ctx->stream) {
        LOG("Cannot create libvirt stream");
        goto cleanup;
    }
    if (virDomainOpenConsole(
            ctx->domain,
            NULL,
            ctx->stream,
            VIR_DOMAIN_CONSOLE_FORCE |
            VIR_DOMAIN_CONSOLE_SAFE) < 0) {
        LOG("Cannot open VM console: %s",
            virGetLastError()->message);
        goto cleanup;
    }
    if (pthread_create(
            &ctx->reader_thread,
            NULL,
            console_reader,
            ctx) != 0) {
        LOG("Cannot create console reader thread");
        goto cleanup;
    }
    ctx->reader_started = 1;
    console_writer(ctx);
cleanup:
    LOG("Closing console session");
    shutdown(ctx->client_fd, SHUT_RDWR);
    /*
     * Abort the stream to release a reader blocked in Recv.
     */
    if (ctx->stream)
        virStreamAbort(ctx->stream);
    if (ctx->reader_started) {
        pthread_join(ctx->reader_thread, NULL);
        ctx->reader_started = 0;
    }
    if (ctx->stream) {
        virStreamFree(ctx->stream);
        ctx->stream = NULL;
    }
    close(ctx->client_fd);
    ctx->client_fd = -1;
    LOG("Client disconnected");
    return 0;
}
/* ---------------------------------------------------------- */
/* Initialization                                             */
/* ---------------------------------------------------------- */
static int context_init(
    struct console_ctx *ctx,
    const char *uri,
    const char *uuid)
{
    memset(ctx, 0, sizeof(*ctx));
    ctx->server_fd = -1;
    ctx->client_fd = -1;
    if (!uuid || strlen(uuid) != VIR_UUID_STRING_BUFLEN - 1) {
        LOG("Invalid UUID: %s", uuid ? uuid : "(null)");
        return -1;
    }
    snprintf(ctx->uuid, sizeof(ctx->uuid), "%s", uuid);
    if (snprintf(ctx->socket_path,
                 sizeof(ctx->socket_path),
                 "/tmp/.display.%s", uuid)
        >= (int)sizeof(ctx->socket_path)) {
        LOG("Socket path too long");
        return -1;
    }
    ctx->conn = virConnectOpen(uri);
    if (!ctx->conn) {
        LOG("Cannot connect to libvirt: %s",
            virGetLastError()->message);
        return -1;
    }
    ctx->domain = virDomainLookupByUUIDString(ctx->conn, uuid);
    if (!ctx->domain) {
        LOG("Cannot find VM %s: %s",
            uuid, virGetLastError()->message);
        return -1;
    }
    if (wait_for_guest(ctx) < 0) {
        LOG("VM is not running");
        return -1;
    }
    ctx->server_fd = create_unix_server(ctx->socket_path);
    if (ctx->server_fd < 0) {
        LOG("Cannot create UNIX socket %s: %s",
            ctx->socket_path, strerror(errno));
        return -1;
    }
    LOG("Socket server created: %s", ctx->socket_path);
    return 0;
}
/* ---------------------------------------------------------- */
/* Cleanup                                                    */
/* ---------------------------------------------------------- */
static void context_cleanup(struct console_ctx *ctx)
{
    if (ctx->client_fd >= 0)
        close(ctx->client_fd);
    if (ctx->stream) {
        virStreamAbort(ctx->stream);
        virStreamFree(ctx->stream);
    }
    if (ctx->server_fd >= 0)
        close(ctx->server_fd);
    if (ctx->domain)
        virDomainFree(ctx->domain);
    if (ctx->conn)
        virConnectClose(ctx->conn);
    if (ctx->socket_path[0])
        unlink(ctx->socket_path);
    LOG("Server stopped");
}
/* ---------------------------------------------------------- */
/* Main                                                       */
/* ---------------------------------------------------------- */
int main(int argc, char **argv)
{
    struct console_ctx ctx;
    if (argc != 3) {
        fprintf(stderr,
                "Usage: %s <libvirt-uri> <uuid>\n",
                argv[0]);
        return EXIT_FAILURE;
    }
    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);
    signal(SIGPIPE, SIG_IGN);
    if (virInitialize() < 0) {
        LOG("libvirt initialization failed");
        return EXIT_FAILURE;
    }
    if (context_init(&ctx, argv[1], argv[2]) < 0) {
        context_cleanup(&ctx);
        return EXIT_FAILURE;
    }
    while (g_running) {
        if (console_session(&ctx) < 0)
            break;
        break; /* One client session, as in the original */
    }
    context_cleanup(&ctx);
    return EXIT_SUCCESS;
}
