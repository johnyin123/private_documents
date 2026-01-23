#include "http-srv.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define MIN(a, b) (((a) < (b)) ? (a) : (b))
#if defined(_WIN32)
    #include <winsock2.h>
    #include <ws2tcpip.h>
    #define close_socket closesocket
#else
    #define close_socket close
    #include <sys/socket.h>
    #include <arpa/inet.h>
    #include <unistd.h>
    #include <netinet/tcp.h>
    #include <fcntl.h>
#endif

#define HTTP_PORT 8080
#define MAX_BODY_SIZE 4096

int set_sock_nonblock_nodelay(int fd) {
    setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, (void *)&(int){1}, sizeof(int));
#if defined(_WIN32)
    unsigned long mode = 1;
    return ioctlsocket(fd, FIONBIO, &mode);
#else
    int flags = fcntl(fd, F_GETFL);
    return (flags < 0) ? -1 : fcntl(fd, F_SETFL, flags | O_NONBLOCK);
#endif
}
/******************/
static void do_test(const char *req, struct response_t *res);

typedef void (*route_func_t)(const char *req, struct response_t *res);
struct router_t {
    enum method_t method;
    const char* path;
    size_t path_len;
    route_func_t func;
} router[] = {
    {.method = GET, .path = "/test", .path_len=5, .func=do_test},
    {UNKNOWN, NULL, 0, NULL}
};
static route_func_t find_route(enum method_t m, const char *path, size_t len) {
    for(const struct router_t *r = router; r->method != UNKNOWN; r++) {
        if (r->method == m && len == r->path_len && memcmp(path, r->path, len) == 0) {
            debugln("Route: %d, %.*s return %p\n", m, (int)len, path, r->func);
            return r->func;
        }
    }
    debugln("Route: %d, %.*s return NULL\n", m, (int)len, path);
    return NULL;
}
static void do_test(const char *req, struct response_t *res) {
    debugln("----- do_test request: \n%s\n", req);
    res->status = 200;
    res->mime = JSON;
    res->body_len = (size_t)snprintf(res->body, MAX_BODY_SIZE, "{\"success\":true}");
}
int create_tcp_server(const char *addr, int port) {
    int srv_sock;
    struct sockaddr_in sa = { .sin_family = AF_INET, .sin_addr.s_addr = inet_addr(addr), .sin_port = htons(port) };
    if ((srv_sock = socket(AF_INET, SOCK_STREAM, 0)) == -1) return -1;
    setsockopt(srv_sock, SOL_SOCKET, SO_REUSEADDR, (void *)&(int){1}, sizeof(int));
    if (bind(srv_sock,(struct sockaddr*)&sa,sizeof(sa)) == -1 || listen(srv_sock, 5) == -1) {
        close_socket(srv_sock);
#if defined(_WIN32)
        WSACleanup();
#endif
        return -1;
    }
    return srv_sock;
}
int main(const int argc, char const* argv[]) {
#if defined(_WIN32)
    WSADATA wsaData;
    int iResult = WSAStartup(MAKEWORD(2 ,2), &wsaData);
    if (iResult != 0) {
        printf("error at WSASturtup\n");
        return 0;
    }
#endif
    char request_buffer[MAX_REQUEST_LEN];
    char response_body[MAX_BODY_SIZE];
    char output_buffer[MAX_BODY_SIZE + 512]; /*512 for headers*/
    struct sockaddr_in addr;
    int addrlen = sizeof(addr);
    int srv_sock, cli_sock;
    debugln("Listen port %d\n", HTTP_PORT);
    if ((srv_sock = create_tcp_server("127.0.0.1", HTTP_PORT)) == -1) {
        perror("Create socket");
        exit(EXIT_FAILURE);
    }
    while (1) {
        debugln("\n+++++ Waiting  conn +++++\n\n");
        if ((cli_sock = accept(srv_sock, (struct sockaddr*)&addr, (socklen_t*)&addrlen)) < 0) {
            perror("In accept");
            exit(EXIT_FAILURE);
        }
        const ssize_t bytes_read = recv(cli_sock, request_buffer, sizeof(request_buffer), 0);
        if (bytes_read < 0) {
            perror("Read error");
            close_socket(cli_sock);
            continue;
        }
        if (bytes_read == 0) {
            debugln("----- Client closed -----\n");
            close_socket(cli_sock);
            continue;
        }
        debugln("Incoming request: \n\n%.*s\n", (int)bytes_read, request_buffer);
        const enum method_t method = http_method(request_buffer, bytes_read);
        const char* path = http_uri(request_buffer, bytes_read);
        const size_t pathLen = (size_t)strchr(path, ' ') - (size_t)path;
        struct response_t response = { .body = response_body, .time = time(0), };
        route_func_t func = find_route(method, path, pathLen);
        if (func) {
            func(request_buffer, &response);
        } else { /*no found*/
            response.status = 403;
            response.mime = PLAIN_TEXT;
            response.body_len = (size_t)snprintf(response_body, MAX_BODY_SIZE, "Forbidden");
        }
        int len = make_response(&response, output_buffer, sizeof(output_buffer));
        debugln("Response: \n\n%.*s\n", len, output_buffer);
        send(cli_sock, output_buffer, len, 0);
        debugln("----- Response sent -----\n");
        close_socket(cli_sock);
    }
#if defined(_WIN32)
    WSACleanup();
#endif
}
