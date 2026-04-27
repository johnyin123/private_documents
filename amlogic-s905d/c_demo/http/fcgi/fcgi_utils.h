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

enum http_status_t {
    HTTP_200 = 200,
    HTTP_400 = 400,
    HTTP_401 = 401,
    HTTP_403 = 403,
    HTTP_404 = 404,
    HTTP_500 = 500,
};

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
bool get_cmd_output(const char* cmd, char *buf, size_t buf_len);
bool starts_with(const char *str, const char *prefix);
bool ends_with(const char *str, const char *suffix);
bool read_file(const char *path, char *buf, size_t sz);
bool get_column(const char *src, int idx, char *out, size_t out_len, const char delm);
/*----------------------------------------------------------------------------*/
#include "cjson/cJSON.h"
#define PARSE_STR(json, cfg, name, key, dec_func)  { cJSON *item = cJSON_GetObjectItemCaseSensitive(json, key); if (item && cJSON_IsString(item) && item->valuestring) snprintf(cfg->name, sizeof(cfg->name), "%s", item->valuestring); }
#define PARSE_INT(json, cfg, name, key, dec_func)  { cJSON *item = cJSON_GetObjectItemCaseSensitive(json, key); if (item && cJSON_IsNumber(item)) cfg->name = item->valueint; }
#define PARSE_BOOL(json, cfg, name, key, dec_func) { cJSON *item = cJSON_GetObjectItemCaseSensitive(json, key); if (item && cJSON_IsBool(item)) cfg->name = cJSON_IsTrue(item); }
#define PARSE_OBJ(json, cfg, name, key, dec_func)  { cJSON *item = cJSON_GetObjectItemCaseSensitive(json, key); if (item && cJSON_IsObject(item)) dec_func(item, &cfg->name); }
#define DECODE_STEP(json, cfg, kind, name, key, dec_func) PARSE_##kind(json, cfg, name, key, dec_func)
/*----------------------------------------------------------------------------*/
#include <pthread.h>
#include <stdbool.h>
#include <string.h>
#include <stdatomic.h>
struct queue_core {
    int cap, head, tail, count;
    atomic_bool closed;
    pthread_mutex_t lock;
    pthread_cond_t not_empty;
    pthread_cond_t not_full;
};
static inline void __queue_core_init(struct queue_core *q, int cap) {
    q->head = q->tail = q->count = 0;
    q->cap = cap;
    atomic_init(&q->closed, false);
    pthread_mutex_init(&q->lock, NULL);
    pthread_cond_init(&q->not_empty, NULL);
    pthread_cond_init(&q->not_full, NULL);
}
static inline void __queue_core_destroy(struct queue_core *q) {
    pthread_mutex_destroy(&q->lock);
    pthread_cond_destroy(&q->not_empty);
    pthread_cond_destroy(&q->not_full);
}

static inline void __queue_core_close(struct queue_core *q) {
    atomic_store(&q->closed, true);
    pthread_mutex_lock(&q->lock);
    pthread_cond_broadcast(&q->not_full);
    pthread_cond_broadcast(&q->not_empty);
    pthread_mutex_unlock(&q->lock);
}

#define DEFINE_QUEUE_TYPE(T, name, CAP)                                       \
                                                                              \
typedef struct {                                                              \
    struct queue_core core;                                                   \
    T *buf[CAP];                                                              \
} name##_t;                                                                   \
                                                                              \
static inline void name##_init(name##_t *q) {                                 \
    __queue_core_init(&q->core, CAP);                                         \
}                                                                             \
                                                                              \
static inline void name##_close(name##_t *q) {                                \
    __queue_core_close(&q->core);                                             \
}                                                                             \
                                                                              \
static inline void name##_destroy(name##_t *q) {                              \
    __queue_core_destroy(&q->core);                                           \
}                                                                             \
                                                                              \
static inline bool name##_push(name##_t *q, T *item) {                        \
    pthread_mutex_lock(&q->core.lock);                                        \
    while (q->core.count >= q->core.cap &&                                    \
            !atomic_load(&q->core.closed)) {                                  \
        if(0 != pthread_cond_wait(&q->core.not_full, &q->core.lock)) {        \
            pthread_mutex_unlock(&q->core.lock);                              \
            return false;                                                     \
        }                                                                     \
    }                                                                         \
    if (atomic_load(&q->core.closed)) {                                       \
        pthread_mutex_unlock(&q->core.lock);                                  \
        return false;                                                         \
    }                                                                         \
    q->buf[q->core.tail] = item;                                              \
    q->core.tail = (q->core.tail + 1) % q->core.cap;                          \
    int c = atomic_fetch_add(&q->core.count, 1) + 1;                          \
    if (c == 1)                                                               \
        pthread_cond_signal(&q->core.not_empty);                              \
    pthread_mutex_unlock(&q->core.lock);                                      \
    return true;                                                              \
}                                                                             \
                                                                              \
static inline T *name##_pop(name##_t *q) {                                    \
    pthread_mutex_lock(&q->core.lock);                                        \
    while (q->core.count == 0 &&                                              \
            !atomic_load(&q->core.closed)) {                                  \
        if (pthread_cond_wait(&q->core.not_empty, &q->core.lock) != 0) {      \
            pthread_mutex_unlock(&q->core.lock);                              \
            return NULL;                                                      \
        }                                                                     \
    }                                                                         \
    if ((q->core.count == 0) && atomic_load(&q->core.closed)) {               \
        pthread_mutex_unlock(&q->core.lock);                                  \
        return NULL; /* empty + closed */                                     \
    }                                                                         \
    T *item = q->buf[q->core.head];                                           \
    q->buf[q->core.head] = NULL;                                              \
    q->core.head = (q->core.head + 1) % q->core.cap;                          \
    int c = atomic_fetch_sub(&q->core.count, 1) - 1;                          \
    if (c == q->core.cap - 1)                                                 \
        pthread_cond_signal(&q->core.not_full);                               \
    pthread_mutex_unlock(&q->core.lock);                                      \
    return item;                                                              \
}

#ifdef __cplusplus
}
#endif
#endif
