#include <netdb.h>
#include <stdlib.h>
#include "utils.h"
#include "main.h"
#define CONN_STATE(c, st)    { log_debug("socket=%d, %s => %s", (c)->fd, STATE_STR((c)->state), STATE_STR((st))); (c)->state=(st); }
void close_conn(struct conn_t *c) { CONN_STATE(c, ST_CLOSE); }
#include <inttypes.h>
static inline void log_access(struct conn_t *c) {
    char buf[64] = { 0, };
    time_t tm = time(NULL);
    strftime(buf, sizeof(buf), "%d/%m/%Y:%H:%M:%S %Z", localtime(&tm));
    fprintf(stdout, GREEN "ACCESS:" RESET " %s - - [%s] \"%.*s\" %d %" PRIu64 "\n", c->peer_ip, buf, (int)c->req.target_size, c->req.target, c->status, c->total_write);
}
static void reset_conn(struct conn_t *c, int fd) {
    memset(c, 0, sizeof(struct conn_t));
    buf_reset(&c->rbuf, c->head, sizeof(c->head));
    buf_reset(&c->wbuf, c->wchunk, sizeof(c->wchunk));
    c->fd=fd;
    c->last_active = now_sec();
    CONN_STATE(c, ST_HEAD);
}
static void handle_accept(int srv_sock, struct conn_t *conns, const size_t len) {
    struct sockaddr_storage addr;
    socklen_t addr_len = sizeof(addr);
    int cli_sock = accept(srv_sock, (struct sockaddr *)&addr, &addr_len);
    if(cli_sock<0) {
        int err = sock_errno();
        if(!is_wouldblock(err)) { log_error("accept %d, %s", err, strerror(err)); }
        return;
    }
    char ip_str[INET6_ADDRSTRLEN] = {0};
    char port_str[NI_MAXSERV] = {0};
    int ret = getnameinfo((struct sockaddr *)&addr, addr_len, ip_str, sizeof(ip_str), port_str, sizeof(port_str), NI_NUMERICHOST | NI_NUMERICSERV);
    if(ret != 0) {
        log_error("getnameinfo: %s", gai_strerror(ret));
        close_socket(cli_sock);
        return;
    }
    set_sock_nonblock_nodelay(cli_sock);
    for(size_t i=0; i<len; i++) {
        if(conns[i].state == ST_NONE) {
            conns[i].fd = cli_sock;
            reset_conn(&conns[i], cli_sock);
            CPY_MEM_STR(conns[i].peer_ip, sizeof(conns[i].peer_ip), ip_str, sizeof(ip_str));
            conns[i].peer_port = atoi(port_str);
            log_info("Connection accept: socket=%d, %s:%d", conns[i].fd, conns[i].peer_ip, conns[i].peer_port);
            return;
        }
    }
    log_error("MAX connection %08zx exceed, socket %d(%s:%s) closed", len, cli_sock, ip_str, port_str);
    close_socket(cli_sock);
    return;
}
#define handle_close(c)      __handle_close((c), NULL)
#define idle_close(c)        __handle_close((c), "IDEL ")
static void __handle_close(struct conn_t *c, const char *msg) {
    UNUSED(msg);
    log_debug("%sClose socket=%d, %s:%d", msg ? msg : "", c->fd, c->peer_ip, c->peer_port);
    if(buf_len(&c->rbuf)>0) {
        log_error("socket=%d, %s:%d, rx remaining: %zu", c->fd, c->peer_ip, c->peer_port, buf_len(&c->rbuf));
        hexdump(stderr, buf_buf(&c->rbuf), buf_len(&c->rbuf));
    }
    if(buf_len(&c->wbuf)>0) {
        log_error("socket=%d, %s:%d, tx remaining: %zu", c->fd, c->peer_ip, c->peer_port, buf_len(&c->wbuf));
        hexdump(stderr, buf_buf(&c->wbuf), buf_len(&c->wbuf));
    }
    log_access(c);
    CONN_STATE(c, ST_NONE);
    close_socket(c->fd);
    c->fd = -1;
}
static void handle_head(struct conn_t *c) {
    int ret = parse_request_line(&c->req_parser, &c->req, &c->bytes_parsed, buf_buf(&c->rbuf), buf_len(&c->rbuf));
    switch (ret) {
        case PARSE_OK      : CONN_STATE(c, ST_PROP); return;
        case PARSE_CONTINUE: return;
        case PARSE_BAD_REQ : make_response(c, HTTP_406, MIME_TEXT, ""); break;
        case PARSE_INVALID : make_response(c, HTTP_403, MIME_TEXT, ""); break;
        default            : log_error("socket=%d, %s:%d, parse_request_line=%d", c->fd, c->peer_ip, c->peer_port, ret); break;
    }
    close_conn(c);
}
static void handle_prop(struct conn_t *c) {
    size_t hdr_parsed = 0;
    int ret = parse_headers(&c->hdr_parser, c->hdr, ARRAY_LEN(c->hdr), &c->hdr_count, &hdr_parsed, buf_buf(&c->rbuf)+c->bytes_parsed, buf_len(&c->rbuf)-c->bytes_parsed);
    switch (ret) {
        case PARSE_OK      :
            c->bytes_parsed += hdr_parsed;
            const char *remain = buf_buf(&c->rbuf) + c->bytes_parsed;
            size_t remain_len = buf_len(&c->rbuf) - c->bytes_parsed;
            buf_reset(&c->rbuf, c->rchunk, sizeof(c->rchunk));
            if(remain_len > 0) { buf_push(remain, remain_len, &c->rbuf); }
            if(c->hdr_count > 0) { CONN_STATE(c, ST_BODY); return; }
            make_response(c, HTTP_400, MIME_TEXT, "");
            break;
        case PARSE_CONTINUE: return;
        case PARSE_BAD_REQ : make_response(c, HTTP_406, MIME_TEXT, ""); break;
        case PARSE_INVALID : make_response(c, HTTP_403, MIME_TEXT, ""); break;
        default            : log_error("socket=%d, %s:%d, parse_headers=%d", c->fd, c->peer_ip, c->peer_port, ret); break;
    }
    close_conn(c);
}
static void handle_body(struct conn_t *c) {
    if(c->content_len == 0) {
        char val[HDR_VAL_LEN];
        const struct http_header *content_len = find_hdr("Content-Length", c->hdr, c->hdr_count);
        if(content_len) {
            CPY_MEM_STR(val, sizeof(val), content_len->value, content_len->value_size);
            c->content_len = atoi(val);
        }
    }
    method_func_t func = method2func(http_method(c->req.method, c->req.method_size));
    func(c);
}
void event_loop(int srv_sock) {
    struct conn_t conns[MAX_CONNS] = { 0 };
    for (size_t i = 0; i < ARRAY_LEN(conns); i++) {
        conns[i].fd = -1;
        conns[i].state = ST_NONE;
    }
    fd_set rset,wset;
    for(;;) {
        FD_ZERO(&rset);
        FD_ZERO(&wset);
        FD_SET(srv_sock, &rset);
        int maxfd=srv_sock;
        for(size_t i=0; i<ARRAY_LEN(conns); i++) {
            if(conns[i].state==ST_NONE) continue;
            if(conns[i].state==ST_CLOSE) { handle_close(&conns[i]); continue; }
            FD_SET(conns[i].fd, &rset);
            FD_SET(conns[i].fd, &wset);
            if(conns[i].fd>maxfd) maxfd=conns[i].fd;
        }
        struct timeval timeout = {.tv_sec=POLL_TMOUT,.tv_usec = 0,};
        int nready = select(maxfd+1, &rset, &wset, NULL, &timeout);
        if(nready<0) {
            if(errno == EINTR) continue;
            log_error("select %s", strerror(errno));
            exit(EXIT_FAILURE);
        }
        time_t now = now_sec();
        if(nready==0) { /*timeout*/
            for(size_t i=0; i<ARRAY_LEN(conns); i++) {
                if(conns[i].state!=ST_NONE && (now - conns[i].last_active)>=IDLE_SEC) { idle_close(&conns[i]); }
            }
        }
        if(FD_ISSET(srv_sock, &rset)) { handle_accept(srv_sock, conns, ARRAY_LEN(conns)); }
        for(size_t i=0;i<ARRAY_LEN(conns);i++) {
            if(conns[i].state==ST_NONE) continue;
            if((now - conns[i].last_active)>=IDLE_SEC) { idle_close(&conns[i]); continue; }
            if(FD_ISSET(conns[i].fd,&rset) && buf_avail(&conns[i].rbuf)>0) {
                conns[i].last_active=now;
                /* peer shutdown or fatal error */
                ssize_t n = buf_read_fd(&conns[i].rbuf, conns[i].fd, &(conns[i].total_read));
                if((n == 0) || (n < 0 && !is_wouldblock(sock_errno()))) { handle_close(&conns[i]); continue; }
            }
            if(conns[i].state == ST_HEAD)  { handle_head(&conns[i]); }
            if(conns[i].state == ST_PROP)  { handle_prop(&conns[i]); }
            if(conns[i].state == ST_BODY)  { handle_body(&conns[i]); }
            if(FD_ISSET(conns[i].fd,&wset) && buf_len(&conns[i].wbuf)>0) {
                conns[i].last_active=now;
                ssize_t n = buf_write_fd(&(conns[i].wbuf), conns[i].fd, &(conns[i].total_write));
                /* peer shutdown or fatal error */
                if((n == 0) || (n < 0 && !is_wouldblock(sock_errno()))) { handle_close(&conns[i]); continue; }
            }
            if(conns[i].state == ST_CLOSE) { handle_close(&conns[i]); }
        }
    }
}
