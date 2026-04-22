#ifndef __FCGI_UTILS_H_070301_221462902__INC__
#define __FCGI_UTILS_H_070301_221462902__INC__
#ifdef __cplusplus
extern "C" {
#endif

#include <fcgiapp.h>
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>

extern struct env {
    int trace_level;
} g_env;

#define BUF_SIZE      (8*1024)
#define SRV_INFO      "Server: inner"
#define UNUSED(x)     ((void)(x))
#define ARRAY_LEN(a)  (sizeof(a)/sizeof((a)[0]))

#ifdef DEBUG
#include <time.h>
#ifdef __cplusplus
#define _AUTO_TYPE auto
#else
#define _AUTO_TYPE __auto_type
#endif
#define SHOW_EXECUTION_TIME(func_call) ({ \
    clock_t start = clock(); \
    _AUTO_TYPE _result = (func_call); \
    clock_t end = clock(); \
    double elapsed = (double)(end - start) / CLOCKS_PER_SEC; \
    log_debug("[%s] Duration: %.9f seconds", #func_call, elapsed); \
    _result; \
})
#else
#define SHOW_EXECUTION_TIME(func_call) (func_call)
#endif

#ifdef USE_SYSLOG
#include <syslog.h>
#define log_debug(fmt,args...)  { if(g_env.trace_level>=LOG_DEBUG) syslog(LOG_DEBUG, fmt "\n", ##args); }
#define log_info(fmt,args...)   { if(g_env.trace_level>=LOG_INFO)  syslog(LOG_INFO, fmt "\n", ##args); }
#define log_error(fmt,args...)  { if(g_env.trace_level>=LOG_ERR)   syslog(LOG_ERR, fmt "\n", ##args); }
#else
enum { LOG_EMERG=0, LOG_ALERT=1, LOG_CRIT=2, LOG_ERR=3, LOG_WARNING=4, LOG_NOTICE=5, LOG_INFO=6, LOG_DEBUG=7 };
#define log_debug(fmt,args...)  { if(g_env.trace_level>=LOG_DEBUG) fprintf(stderr, GREEN "DEBUG" RESET " %s:%d " fmt "\n", __FILE__, __LINE__, ##args); }
#define log_info(fmt,args...)   { if(g_env.trace_level>=LOG_INFO)  fprintf(stderr, GREEN "INFO " RESET " %s:%d " fmt "\n", __FILE__, __LINE__, ##args); }
#define log_error(fmt,args...)  { if(g_env.trace_level>=LOG_ERR)   fprintf(stderr, RED   "ERROR" RESET " %s:%d " fmt "\n", __FILE__, __LINE__, ##args); }
#endif

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
#if defined(__WIN32__)
    #define RED
    #define GREEN
    #define RESET
#else
    #define RED   "\033[0;31m"
    #define GREEN "\033[0;32m"
    #define RESET "\033[0m"
#endif
#include <stdio.h>
static inline void _dump_request(FILE *fp, const char *s, FCGX_Request *req, const char *f, int line) {
    fprintf(fp, GREEN "%s" RESET " Request Dump ===\n", s);
    fprintf(fp, "    requestId: %d\n", req->requestId);
    fprintf(fp, "    role: %d\n", req->role);
    fprintf(fp, "  Environment Variables ---\n");
    if (req->envp) {
        for(char **env = req->envp; *env; env++) fprintf(fp, "    %s\n", *env);
    }
    fprintf(fp, "  Streams ---\n");
    fprintf(fp, "    in:  %p\n", (void*)req->in);
    fprintf(fp, "    out: %p\n", (void*)req->out);
    fprintf(fp, "    err: %p\n", (void*)req->err);
}
#define dump_request(s, req) { if(g_env.trace_level>LOG_DEBUG) _dump_request(stderr, s, req, __FILE__, __LINE__); }
/*-------------------------------*/
#include <pthread.h>
struct queue_t {
    void **elems; int cap;
    int head, tail, count;
    pthread_mutex_t mutex;
    pthread_cond_t not_empty;
    pthread_cond_t not_full;
    volatile bool stop;
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
