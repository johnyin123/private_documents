#include <stdio.h>
#include <getopt.h>
#include <stdlib.h>
#include "utils.h"
#include "main.h"
#include "const.h"
#include "http_parser.h"
struct env g_env = {
    .trace_level = LOG_ERR,
    .server_sock = 0,
};
const char *opt_short="h";
struct option opt_long[] = {
    { "help",    no_argument, NULL, 'h' },
    { "version", no_argument, NULL, 256 }, /* values > 255 */
    { 0, 0, 0, 0 }
};
static void usage(const char *prog) {
    fprintf(stderr,
        "Usage: %s\n"
        "    -h|--help help\n"
        "    --version\n"
        , prog);
    exit(0);
}
static int parse_command_line(int argc, char **argv) {
    int opt, option_index;
    while ((opt = getopt_long(argc, argv, opt_short, opt_long, &option_index)) != -1) {
        switch (opt) {
            case 'h':
                usage(argv[0]);
                return 0;
            case 256:
                fprintf(stdout, "version\n");
                return 0;
            default:
                usage(argv[0]);
                return 1;
        }
    }
    return 0;
}
struct conn_t {
    int fd;
    char peer_ip[INET6_ADDRSTRLEN];
    int peer_port;
    uint8_t tick_cnt;
    enum conn_state_t state;
    unsigned int content_len;
    size_t bytes_parsed;
    struct req_line req;
    uint32_t hdr_count;
    struct http_header hdr[MAX_HEADERS];
    struct req_line_parser req_parser;
    struct http_headers_parser hdr_parser;
    struct buf_t rbuf;
    char head[HDR_SIZE];
    char rchunk[BUF_SIZE];
    struct buf_t wbuf;
    char wchunk[BUF_SIZE];
    uint64_t total_read;
    uint64_t total_write;
};
static inline const struct http_header *find_hdr(const char *key, struct http_header *hdr, uint32_t hdr_count) {
    for (size_t i=0;i<hdr_count;i++) {
        if (memcasecmp(key, strlen(key), hdr[i].name, hdr[i].name_size)) { return &hdr[i]; }
    }
    return NULL;
}
static inline void log_bad_req(struct conn_t *c) {
    log_error("bad request %d", c->fd);
}
static inline void log_invalid_req(struct conn_t *c) {
    log_error("invalid request %d", c->fd);
}
static inline void log_access(struct conn_t *c, uint16_t status) {
    log_info("ACCESS: %s:%d, http(%d) parsed(%zu), %.*s", c->peer_ip, c->peer_port, status,  c->bytes_parsed, (int)c->bytes_parsed, c->head);
}
#define CONN_STATE(c, st) { log_debug("socket=%d, %s => %s", (c)->fd, STATE_STR((c)->state), STATE_STR((st))); (c)->state=(st); }
static inline int make_header(struct conn_t *c, uint16_t status, enum mime_t mime, unsigned int content_len) {
    CONN_STATE(c, ST_RESP);
    log_access(c, status);
    //"M(%s) %d.%d %.*s (Content-Length=%d)", METHOD_STR(http_method(c->req.method, c->req.method_size)), c->req.httpver_major, c->req.httpver_minor, c->req.target_size, c->req.target, c->content_len);

    return buf_printf(&c->wbuf, "HTTP/1.1 %d %s\r\n%s\r\nContent-Type: %s\r\nConnection: %s\r\nContent-Length: %d\r\n\r\n", status, STATUS_STR(status), SRV_INFO, MIME_STR(mime), "close", content_len);
}
static inline int make_response(struct conn_t *c, uint16_t status, enum mime_t mime, const char *format, ...) {
    va_list args;
    char buf[BUF_SIZE];
    struct buf_t body;
    buf_reset(&body, buf, sizeof(buf));
    va_start(args, format);
    int hdr_len = buf_vprintf(&body, format, args);
    va_end(args);
    if(hdr_len<0) return hdr_len; /*format = ""*/
    int body_len = make_header(c, status, mime, hdr_len);
    if(body_len<=0) return body_len;
    int ret = buf_push(body.buf, body.len, &c->wbuf);
    if(ret<0) return ret; /*format = ""*/
    if(c->state!=ST_RESP) CONN_STATE(c, ST_RESP);
    return ret + hdr_len;
}
static void cleanup() {
    log_info("cleanup");
    if(g_env.server_sock>0) close_socket(g_env.server_sock);
#if defined(__WIN32__)
    WSACleanup();
#endif
}
static void reset_conn(struct conn_t *c, int fd) {
    uint64_t total_read = 0;
    uint64_t total_write = 0;
    if((fd >= 0) && (fd == c->fd)) {
        total_read = c->total_read;
        total_write = c->total_write;
    }
    memset(c, 0, sizeof(struct conn_t));
    CONN_STATE(c, ST_HEAD);
    buf_reset(&c->rbuf, c->head, sizeof(c->head));
    buf_reset(&c->wbuf, c->wchunk, sizeof(c->wchunk));
    c->total_read = total_read;
    c->total_write = total_write;
    c->fd=fd;
}
#include <netdb.h>
static void handle_accept(int srv_sock, struct conn_t *conns, const size_t len) {
    struct sockaddr_storage addr;
    socklen_t addr_len = sizeof(addr);
    int cli_sock = accept(srv_sock, (struct sockaddr *)&addr, &addr_len);
    if(cli_sock<0) {
        int err = sock_errno();
        if(!is_wouldblock(err)) { log_error("accept %d", err); }
        return;
    }
    char ip_str[INET6_ADDRSTRLEN] = {0};
    char port_str[NI_MAXSERV] = {0};
    int ret = getnameinfo((struct sockaddr *)&addr, addr_len, ip_str, sizeof(ip_str), port_str, sizeof(port_str), NI_NUMERICHOST | NI_NUMERICSERV);
    if (ret != 0) {
        log_error("getnameinfo: %s", gai_strerror(ret));
        close_socket(cli_sock);
        return;
    }
    set_sock_nonblock_nodelay(cli_sock);
    log_info("Connect %d accept", cli_sock);
    for(size_t i=0; i<len; i++) {
        if(conns[i].state == ST_NONE) {
            conns[i].fd = cli_sock;
            reset_conn(&conns[i], cli_sock);
            CPY_MEM_STR(conns[i].peer_ip, sizeof(conns[i].peer_ip), ip_str, sizeof(ip_str));
            conns[i].peer_port = atoi(port_str);
            return;
        }
    }
    log_error("max connection %08zx exceed, socket %d closed", len, cli_sock);
    close_socket(cli_sock);
    return;
}
static void handle_close(struct conn_t *c) {
    log_debug("Close %d", c->fd);
    CONN_STATE(c, ST_NONE);
    close_socket(c->fd);
    c->fd = -1;
}
static void handle_head(struct conn_t *c) {
    int ret = parse_request_line(&c->req_parser, &c->req, &c->bytes_parsed, buf_buf(&c->rbuf), buf_len(&c->rbuf));
    switch (ret) {
        case PARSE_OK      : CONN_STATE(c, ST_PROP); return;
        case PARSE_CONTINUE: return;
        case PARSE_BAD_REQ : log_bad_req(c); break;
        case PARSE_INVALID : log_invalid_req(c); break;
        default            : log_error("parse_request_line unknow %d", ret); break;
    }
    handle_close(c);
}
static void handle_prop(struct conn_t *c) {
    size_t hdr_parsed = 0;
    int ret = parse_headers(&c->hdr_parser, c->hdr, ARRAY_LEN(c->hdr), &c->hdr_count, &hdr_parsed, buf_buf(&c->rbuf)+c->bytes_parsed, buf_len(&c->rbuf)-c->bytes_parsed);
    switch (ret) {
        case PARSE_OK      :
            c->bytes_parsed += hdr_parsed;
            CONN_STATE(c, ST_BODY);
            const char *remain = buf_buf(&c->rbuf);
            size_t remain_len = buf_len(&c->rbuf) - c->bytes_parsed;
            buf_reset(&c->rbuf, c->rchunk, sizeof(c->rchunk));
            if(remain_len > 0) { buf_push(remain, remain_len, &c->rbuf); }
            return;
        case PARSE_CONTINUE: return;
        case PARSE_BAD_REQ : log_bad_req(c); break;
        case PARSE_INVALID : log_invalid_req(c); break;
        default            : log_error("parse_headers unknow %d", ret); break;
    }
    handle_close(c);
}
static void handle_body(struct conn_t *c) {
    char val[HDR_VAL_LEN];
    const struct http_header *content_len = find_hdr("Content-Length", c->hdr, c->hdr_count);
    if(content_len) {
        CPY_MEM_STR(val, sizeof(val), content_len->value, content_len->value_size);
        c->content_len = atoi(val);
    }
    if(buf_len(&c->rbuf) != c->bytes_parsed && c->content_len!=0) {
        const char *msg = "Bad Request!!!";
        make_response(c, HTTP_400, MIME_TEXT, "%.*s", strlen(msg), msg);
        return;
    }
    make_response(c, HTTP_200, MIME_TEXT, "M(%s) %d.%d %.*s (Content-Length=%d) parsed %zu", METHOD_STR(http_method(c->req.method, c->req.method_size)), c->req.httpver_major, c->req.httpver_minor, c->req.target_size, c->req.target, c->content_len, c->bytes_parsed);
}
static void handle_resp(struct conn_t *c) {
    ssize_t n = buf_write_fd(&(c->wbuf), c->fd, &(c->total_write));
    /* peer shutdown or fatal error */
    if ((n == 0) || (n < 0 && !is_wouldblock(sock_errno()))) { CONN_STATE(c, ST_CLOSE); }
}
static void event_loop() {
    struct conn_t conns[MAX_CONNS] = { 0 };
    for (size_t i = 0; i < ARRAY_LEN(conns); i++) {
        conns[i].fd = -1;
        conns[i].state = ST_NONE;
    }
    fd_set rset,wset;
    for(;;) {
        FD_ZERO(&rset);
        FD_ZERO(&wset);
        FD_SET(g_env.server_sock, &rset);
        int maxfd=g_env.server_sock;
        for(size_t i=0; i<ARRAY_LEN(conns); i++) {
            struct conn_t *c = &conns[i];
            switch (c->state) {
                case ST_HEAD  :
                case ST_PROP  :
                case ST_BODY  : FD_SET(c->fd, &rset); break;
                case ST_RESP  : FD_SET(c->fd, &wset); break;
                case ST_CLOSE : handle_close(c); break;
                default       : continue;
            }
            if(c->fd>maxfd) maxfd=c->fd;
        }
        struct timeval timeout = {.tv_sec=POLL_TMOUT,.tv_usec = 0,};
        int nready = select(maxfd+1, &rset, &wset, NULL, &timeout);
        if(nready<0) {
            if (errno == EINTR) continue;
            log_error("select %s", strerror(errno));
            exit(EXIT_FAILURE);
        }
        if(nready==0) { /*timeout*/
            for(size_t i=0; i<ARRAY_LEN(conns); i++) {
                if(conns[i].state!=ST_NONE && ++conns[i].tick_cnt>=IDEL_TICK) {
                    log_debug("IDEL TIMEOUT %d", conns[i].fd);
                    handle_close(&conns[i]);
                }
            }
            continue;
        }
        if(FD_ISSET(g_env.server_sock, &rset)) {
            handle_accept(g_env.server_sock, conns, ARRAY_LEN(conns));
        }
        for(size_t i=0;i<ARRAY_LEN(conns);i++) {
            if(conns[i].state==ST_NONE) continue;
            if(conns[i].tick_cnt>=IDEL_TICK) {
                log_debug("IDEL TIMEOUT %d", conns[i].fd);
                handle_close(&conns[i]);
                continue; 
            }
            if(FD_ISSET(conns[i].fd,&rset)) {
                if(buf_avail(&conns[i].rbuf) > 0) { conns[i].tick_cnt=0; }
                ssize_t n = buf_read_fd(&conns[i].rbuf, conns[i].fd, &(conns[i].total_read));
                if ((n == 0) || (n < 0 && !is_wouldblock(sock_errno()))) { CONN_STATE(&conns[i], ST_CLOSE); } /* peer shutdown or fatal error */
                if(conns[i].state == ST_HEAD)  { handle_head(&conns[i]); }
                if(conns[i].state == ST_PROP)  { handle_prop(&conns[i]); }
                if(conns[i].state == ST_BODY)  { handle_body(&conns[i]); }
                if(conns[i].state == ST_CLOSE) { handle_close(&conns[i]); }
            }
            if(FD_ISSET(conns[i].fd,&wset)) { conns[i].tick_cnt=0; handle_resp(&conns[i]); }
        }
    }
}
#include <signal.h>
void sig_func(int sig) { UNUSED(sig); exit(EXIT_FAILURE); }
int main(int argc, char *argv[]) {
    const char* e_val = getenv("TRACE");
    if (e_val) g_env.trace_level = atoi(e_val);
    parse_command_line(argc, argv);
#if defined(__WIN32__)
    WSADATA wsaData;
    int iResult = WSAStartup(MAKEWORD(2 ,2), &wsaData);
    if(iResult != 0) { log_error("error at WSASturtup %d", iResult); return EXIT_SUCCESS; }
#else
    signal(SIGPIPE, SIG_IGN);
#endif
    atexit(cleanup);
    signal(SIGINT, sig_func);
    signal(SIGTERM, sig_func);
    g_env.server_sock = create_tcp_server("127.0.0.1", HTTP_PORT, 10);
    if(g_env.server_sock>0) event_loop();
    log_info("Exit");
    return 0;
}
