#ifndef __FCGI_UTILS_H_070301_221462902__INC__
#define __FCGI_UTILS_H_070301_221462902__INC__
#ifdef __cplusplus
extern "C" {
#endif

#include <fcgiapp.h>
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>

#define BUF_SIZE      (8*1024)
#define SRV_INFO      "Server: inner"
#define UNUSED(x)     ((void)(x))
#define ARRAY_LEN(a)  (sizeof(a)/sizeof((a)[0]))

#define S_METHOD(X) \
    X(METHOD_NONE,     NONE) \
    X(METHOD_GET,      GET) \
    X(METHOD_POST,     POST) \
    X(METHOD_HEAD,     HEAD)

#define S_MIME_TYPE(X) \
    X(MIME_BIN,       application/octet-stream) \
    X(MIME_JSON,      application/json; charset=utf-8) \
    X(MIME_TEXT,      text/plain; charset=utf-8)

#define _ITEM(c, n)   c,
enum method_t         { S_METHOD(_ITEM) };
enum mime_t           { S_MIME_TYPE(_ITEM) };
#undef _ITEM
const char *code2str(const uint16_t code, const char *tbl[], const size_t len, const char *nodef);
enum method_t http_method(const char *m, size_t len);
const char* req_get_header(FCGX_Request *r, const char *key);
const char* req_method(FCGX_Request *r);
const char* req_uri(FCGX_Request *r);
const char* req_query(FCGX_Request *r);
const char* req_cookie(FCGX_Request *r);
int req_content_length(FCGX_Request *r);
bool query_get(const char *qs, const char *key, char *out, size_t out_sz);
void url_decode(char *s);
int req_body(FCGX_Request *req, char *out, size_t out_len);
void make_response(FCGX_Request *req, uint16_t status, enum mime_t mime, const char *format, ...);
/*-------------------------------*/
#include <pthread.h>
struct queue_t {
    void **elems; int cap;
    int head, tail, count;
    pthread_mutex_t mutex;
    pthread_cond_t not_empty;
    pthread_cond_t not_full;
    volatile int stop;
};
void queue_init(struct queue_t *q, void *elems, size_t size);
void queue_stop(struct queue_t *q);
void queue_destroy(struct queue_t *q);
int queue_push(struct queue_t *q, void *elem);
void *queue_pop(struct queue_t *q);
/*-------------------------------*/

#ifdef __cplusplus
}
#endif
#endif
