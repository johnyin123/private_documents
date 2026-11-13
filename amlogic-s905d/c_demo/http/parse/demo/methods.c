#include "utils.h"
#include "main.h"
void METHOD_FUNC_NONE(struct conn_t *c) {
    make_response(c, HTTP_501, MIME_TEXT, "");
}
void METHOD_FUNC_GET(struct conn_t *c) {
    make_response(c, HTTP_200, MIME_TEXT, "M(%s) %d.%d %.*s (Content-Length=%d) parsed %zu", METHOD_STR(http_method(c->req.method, c->req.method_size)), c->req.httpver_major, c->req.httpver_minor, c->req.target_size, c->req.target, c->content_len, c->bytes_parsed);
    close_conn(c);
}
void METHOD_FUNC_POST(struct conn_t *c) {
    if (c->content_len == 0) { make_response(c, HTTP_400, MIME_TEXT, ""); return; }
    if (!c->ctx) {
        c->ctx = (void *)(intptr_t)1; 
        make_header(c, HTTP_200, MIME_BIN, c->content_len);
    }
    const char *body = buf_buf(&c->rbuf);
    size_t body_len = buf_len(&c->rbuf);
    size_t send_avail = buf_avail(&c->wbuf);
    if ((body_len > 0) && (send_avail > 0)) {
        int pushed = buf_push(body, body_len, &c->wbuf);
        if (pushed < 0) { return; }
        buf_remove_head(&c->rbuf, pushed);
    }
}
void METHOD_FUNC_PUT(struct conn_t *c) {
    make_response(c, HTTP_501, MIME_TEXT, "");
}
void METHOD_FUNC_DELETE(struct conn_t *c) {
    make_response(c, HTTP_501, MIME_TEXT, "");
}
void METHOD_FUNC_HEAD(struct conn_t *c) {
    make_response(c, HTTP_501, MIME_TEXT, "");
}
void METHOD_FUNC_OPTIONS(struct conn_t *c) {
    make_response(c, HTTP_501, MIME_TEXT, "");
}
void METHOD_FUNC_PATCH(struct conn_t *c) {
    make_response(c, HTTP_501, MIME_TEXT, "");
}
void METHOD_FUNC_TRACE(struct conn_t *c) {
    make_response(c, HTTP_501, MIME_TEXT, "");
}
void METHOD_FUNC_CONNECT(struct conn_t *c) {
    make_response(c, HTTP_501, MIME_TEXT, "");
}
