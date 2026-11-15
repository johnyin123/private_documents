#include "main.h"
void METHOD_FUNC_NONE(struct conn_t *c) {
    make_header(c, HTTP_501, MIME_TEXT, 0, HDR_CLOSE);
}
void METHOD_FUNC_GET(struct conn_t *c) {
    int len = snprintf(NULL, 0, "M(%s) %d.%d %.*s (Content-Length=%d) parsed %zu", METHOD_STR(http_method(c->req.method, c->req.method_size)), c->req.httpver_major, c->req.httpver_minor, (int)c->req.target_size, c->req.target, (int)c->content_len, c->bytes_parsed);
    make_header(c, HTTP_200, MIME_TEXT, len, HDR_CLOSE);
    make_response(c, "M(%s) %d.%d %.*s (Content-Length=%d) parsed %zu", METHOD_STR(http_method(c->req.method, c->req.method_size)), c->req.httpver_major, c->req.httpver_minor, (int)c->req.target_size, c->req.target, (int)c->content_len, c->bytes_parsed);
    close_conn(c);
}
void METHOD_FUNC_POST(struct conn_t *c) {
    if(c->content_len == 0) { make_header(c, HTTP_400, MIME_TEXT, 0, HDR_CLOSE); return; }
    if(!c->status) { make_header(c, HTTP_200, MIME_BIN, c->content_len, HDR_CLOSE); }
    const char *body = buf_buf(&c->rbuf);
    size_t body_len = buf_len(&c->rbuf);
    size_t send_avail = buf_avail(&c->wbuf);
    if((body_len > 0) && (send_avail > 0)) {
        int pushed = buf_push(body, body_len, &c->wbuf);
        if(pushed < 0) { return; }
        buf_remove_head(&c->rbuf, pushed);
        c->ctx.st_size += pushed;
    }
    if(c->ctx.st_size >= c->content_len) { close_conn(c); }
}
void METHOD_FUNC_PUT(struct conn_t *c) {
    make_header(c, HTTP_501, MIME_TEXT, 0, HDR_CLOSE);
}
void METHOD_FUNC_DELETE(struct conn_t *c) {
    make_header(c, HTTP_501, MIME_TEXT, 0, HDR_CLOSE);
}
void METHOD_FUNC_HEAD(struct conn_t *c) {
    make_header(c, HTTP_501, MIME_TEXT, 0, HDR_CLOSE);
}
void METHOD_FUNC_OPTIONS(struct conn_t *c) {
    make_header(c, HTTP_501, MIME_TEXT, 0, HDR_CLOSE);
}
void METHOD_FUNC_PATCH(struct conn_t *c) {
    make_header(c, HTTP_501, MIME_TEXT, 0, HDR_CLOSE);
}
void METHOD_FUNC_TRACE(struct conn_t *c) {
    make_header(c, HTTP_501, MIME_TEXT, 0, HDR_CLOSE);
}
void METHOD_FUNC_CONNECT(struct conn_t *c) {
    make_header(c, HTTP_501, MIME_TEXT, 0, HDR_CLOSE);
}
