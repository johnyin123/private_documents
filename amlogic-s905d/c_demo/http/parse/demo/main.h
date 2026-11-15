#ifndef __MAIN_H_101655_4178806362__INC__
#define __MAIN_H_101655_4178806362__INC__
#ifdef __cplusplus
extern "C" {
#endif

#ifdef HAVE_CONFIG_H
#  include "config.h"
#endif

#if defined(__WIN32__)
    #include <winsock2.h>
    #include <ws2tcpip.h>
    typedef int socklen_t;
    #define close_socket closesocket
    #define sock_read(a,b,c)  recv(a,b,c,0)
    #define sock_write(a,b,c) send(a,b,c,0)
    static inline void* memmem(const void* haystack, size_t haystacklen, const void* needle, size_t needlelen) { if(!needlelen) return (void*)haystack;
        for(size_t i = 0; i + needlelen <= haystacklen; i++) {
            if(!memcmp((char*)haystack + i, needle, needlelen)) return (char*)haystack + i;
        }
        return NULL;
    }
    #define sock_errno() WSAGetLastError()
#else
    #define close_socket close
    #define sock_read(a,b,c)  read(a,b,c)
    #define sock_write(a,b,c) write(a,b,c)
    #include <sys/socket.h>
    #include <arpa/inet.h>
    #include <unistd.h>
    #include <netinet/tcp.h>
    #include <fcntl.h>
    #include <errno.h>
    #define sock_errno() errno
#endif
#include "utils.h"
static inline int is_wouldblock(int e) { return e == EAGAIN || e == EWOULDBLOCK; }
static inline int set_sock_nonblock_nodelay(int fd) {
    setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, (void *)&(int){1}, sizeof(int));
#if defined(__WIN32__)
    unsigned long mode = 1;
    return ioctlsocket(fd, FIONBIO, &mode);
#else
    int flags = fcntl(fd, F_GETFL);
    return (flags < 0) ? -1 : fcntl(fd, F_SETFL, flags | O_NONBLOCK);
#endif
}
#include <string.h>
static inline int create_tcp_server(const char *addr, int port, int backlog) {
    int srv_sock;
    struct sockaddr_in sa = { .sin_family = AF_INET, .sin_addr.s_addr = inet_addr(addr), .sin_port = htons(port) };
    if((srv_sock = socket(AF_INET, SOCK_STREAM, 0))<0) return -1;
    setsockopt(srv_sock, SOL_SOCKET, SO_REUSEADDR, (void *)&(int){1}, sizeof(int));
    if(bind(srv_sock,(struct sockaddr*)&sa,sizeof(sa))<0 || listen(srv_sock, backlog)<0) {
        log_error("create socket %s", strerror(errno));
        close_socket(srv_sock);
        return -1;
    }
    set_sock_nonblock_nodelay(srv_sock);
    return srv_sock;
}
struct buf_t {
    char *buf;
    size_t len; /*used size*/
    size_t capacity; /*buf size*/
};
static inline int buf_reset(struct buf_t *b, char *buf, size_t capacity) { b->buf=buf; b->capacity=capacity; b->len=0; return 0; }
static inline const char *buf_buf(const struct buf_t *b) { return b->buf; }
static inline size_t buf_len(const struct buf_t *b) { return b->len; }
static inline size_t buf_avail(const struct buf_t *b) { return b->capacity - b->len; }
static inline void buf_remove_head(struct buf_t *b, size_t n) {
    if(n >= b->len) b->len = 0;
    else memmove(b->buf, b->buf + n, b->len -= n);
}
static inline int buf_pop(char *dest, size_t len, struct buf_t *b) {
    int n=(len>b->len?b->len:len);
    memcpy(dest, b->buf, n);
    buf_remove_head(b, n);
    return n;
}
static inline int buf_push(const char *src, size_t len, struct buf_t *b) {
    if(buf_avail(b)<len) return -1;
    memcpy(b->buf + b->len, src, len);
    b->len+=len;
    return len;
}
static inline int buf_vprintf(struct buf_t *b, const char *format, va_list args) {
    size_t avail = buf_avail(b);
    int n = vsnprintf(b->buf + b->len, avail, format, args);
    if(n < 0) return -1;
    if((size_t)n >= avail) {
        b->len += avail;
        return -2;
    }
    b->len += n;
    return n;
}
#include <stdarg.h>
static inline int buf_printf(struct buf_t *b, const char *format, ...) {
    va_list args;
    va_start(args, format);
    int n = buf_vprintf(b, format, args);
    va_end(args);
    return n;
}
static inline ssize_t buf_read_fd(struct buf_t *b, int fd, uint64_t *total) {
    if(buf_avail(b)<=0) return -1;
    ssize_t n = sock_read(fd, b->buf + b->len, buf_avail(b));
    if(n > 0) {
        b->len += n;
        if(total) *total += n;
    }
    return n;
}
static inline ssize_t buf_write_fd(struct buf_t *b, int fd, uint64_t *total) {
    ssize_t n = sock_write(fd, b->buf, b->len);
    if(n > 0) {
        if(total) *total += n;
        buf_remove_head(b, n);
    }
    return n;
}
static inline ssize_t buf_read_fp(struct buf_t *b, FILE *fp, unsigned int *total) {
    if(buf_avail(b)<=0) return -1;
    ssize_t n = fread(b->buf + b->len, 1, buf_avail(b), fp);
    if(n > 0) {
        b->len += n;
        if(total) *total += n;
    }
    return n;
}
static inline ssize_t buf_write_fp(struct buf_t *b, FILE *fp, unsigned int *total) {
    ssize_t n = fwrite(b->buf, 1, b->len, fp);
    if(n > 0) {
        if(total) *total += n;
        buf_remove_head(b, n);
    }
    return n;
}
#include <ctype.h>
static inline bool memcasecmp(const void *buf1, size_t buf1_len, const char *buf2, size_t buf2_len) {
    if(buf1_len != buf2_len) return false;
    const unsigned char *b = buf1;
    for(size_t i = 0; i < buf1_len; i++) {
        if(tolower((unsigned char)buf2[i]) != tolower(b[i])) return false;
    }
    return true;
}
static inline void hexdump(FILE *fp, const void *ptr, size_t len) {
    const unsigned char *buf = ptr;
    for(size_t i = 0; i < len; i += 16, fprintf(fp, "\n")) {
        fprintf(fp, "%08zx: ", i);
        for(size_t j = 0; j < 16; j++)
            i+j < len ? fprintf(fp, "%02x ", buf[i+j]) : fprintf(fp, "   ");
        fprintf(fp, " |");
        for(int j = 0; j < 16 && i+j < len; j++)
            fprintf(fp, "%c", isprint(buf[i+j]) ? buf[i+j] : '.');
        fprintf(fp, "|");
    }
}
#include <time.h>
static inline bool rfc1123_date(char *dest, size_t len, const time_t when) {
    time_t when_copy = when;
    if(strftime(dest, len, "%a, %d %b %Y %H:%M:%S GMT", gmtime(&when_copy)) == 0)
        return false;
    return true;
}
static inline time_t now_sec() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec;
}
#define SRV_INFO      "Server: inner"
#define IDLE_SEC      10
#define POLL_TMOUT    2   /* POLL_TMOUT */
#ifndef CONFIG_MAX_CONNS
#define CONFIG_MAX_CONNS     64  /* < FD_SETSIZE */
#endif
#ifndef CONFIG_MAX_HEADERS
#define CONFIG_MAX_HEADERS   8
#endif
#ifndef CONFIG_HDR_SIZE
#define CONFIG_HDR_SIZE      (4*1024)
#endif
#ifndef CONFIG_BUF_SIZE
#define CONFIG_BUF_SIZE      (8*1024)
#endif
#include "http_parser.h"
#include "const.h"
struct conn_t {
    int fd;
    char peer_ip[INET6_ADDRSTRLEN];
    uint16_t peer_port;
    time_t last_active;
    enum conn_state_t state;
    unsigned int content_len;
    size_t bytes_parsed;
    uint16_t status; /* response code */
    struct req_line req;
    uint32_t hdr_count;
    struct http_header hdr[CONFIG_MAX_HEADERS];
    struct req_line_parser req_parser;
    struct http_headers_parser hdr_parser;
    struct buf_t rbuf;
    char head[CONFIG_HDR_SIZE];
    char rchunk[CONFIG_BUF_SIZE];
    struct buf_t wbuf;
    char wchunk[CONFIG_BUF_SIZE];
    uint64_t total_read;
    uint64_t total_write;
    struct {
        FILE *fp;
        off_t st_size;
    } ctx;
};
static inline const struct http_header *find_hdr(const char *key, struct http_header *hdr, uint32_t hdr_count) {
    for(size_t i=0;i<hdr_count;i++) {
        if(memcasecmp(key, strlen(key), hdr[i].name, hdr[i].name_size)) { return &hdr[i]; }
    }
    return NULL;
}
#define make_response(c, fmt, args...)  buf_printf(&(c)->wbuf, fmt, ##args)
#define HDR_CLOSE         "Connection: close"
#define HDR_KEEP_ALIVE    "Connection: keep-alive"
static inline int make_header(struct conn_t *c, uint16_t status, enum mime_t mime, unsigned int content_len, ...) {
    if(c->status) { log_error("socket=%d, %s:%d, status: %d -> %d", c->fd, c->peer_ip, c->peer_port, c->status, status); }
    c->status = status;
    int written = buf_printf(&c->wbuf, "HTTP/1.1 %d %s\r\n%s\r\nContent-Type: %s\r\n", status, STATUS_STR(status), SRV_INFO, MIME_STR(mime));
    if(written < 0) { return written; }
    if(content_len > 0) {
        int extra = buf_printf(&c->wbuf, "Content-Length: %d\r\n", content_len);
        if(extra < 0) { return extra; }
        written += extra;
    }
    va_list args;
    va_start(args, content_len);
    for(;;) {
        const char *next_header = va_arg(args, const char *);
        if(next_header == NULL) { break; }
        int extra = buf_printf(&c->wbuf, "%s\r\n", next_header);
        if(extra < 0) { va_end(args); return extra; }
        written += extra;
    }
    int last = buf_printf(&c->wbuf, "\r\n");
    va_end(args);
    if(last < 0) { return last; }
    written += last;
    return written;
}
void close_conn(struct conn_t *c);
typedef void (*method_func_t)(struct conn_t *c);
extern const method_func_t method_funcs[];
extern const size_t method_funcs_len;
void METHOD_FUNC_NONE(struct conn_t *c);
void METHOD_FUNC_GET(struct conn_t *c);
void METHOD_FUNC_POST(struct conn_t *c);
void METHOD_FUNC_PUT(struct conn_t *c);
void METHOD_FUNC_DELETE(struct conn_t *c);
void METHOD_FUNC_HEAD(struct conn_t *c);
void METHOD_FUNC_OPTIONS(struct conn_t *c);
void METHOD_FUNC_PATCH(struct conn_t *c);
void METHOD_FUNC_TRACE(struct conn_t *c);
void METHOD_FUNC_CONNECT(struct conn_t *c);
#define method2func(c)  (method_func_t)code2ptr((c), (const void **)method_funcs, method_funcs_len, METHOD_FUNC_NONE)
void event_loop(int srv_sock);

#ifdef __cplusplus
}
#endif
#endif
