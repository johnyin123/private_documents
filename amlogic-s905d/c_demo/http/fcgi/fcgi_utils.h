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
bool get_cmd_output(const char* cmd, char *buf, size_t buf_len);
bool starts_with(const char *str, const char *prefix);
bool ends_with(const char *str, const char *suffix);
bool read_file(const char *path, char *buf, size_t sz);
bool get_column(const char *src, int idx, char *out, size_t out_len, const char delm);
/*-------------------------------*/
#include <pthread.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <string.h>
//static inline bool is_power_of_2(uint32_t n) { return n > 0 && (n & (n - 1)) == 0; }
#if __STDC_VERSION__ >= 201112L
    #define STATIC_ASSERT(cond, msg) _Static_assert(cond, msg)
#else
    #define STATIC_ASSERT(cond, msg) typedef char static_assert_##msg[(cond)?1:-1]
#endif

#define IS_POWER_OF_TWO(x) ((x) && !((x) & ((x) - 1)))
typedef struct {
    void *data;
    atomic_uint seq;
} mpmc_cell_t;
typedef struct {
    mpmc_cell_t *buffer;
    uint32_t mask;
    atomic_uint head;
    atomic_uint tail;
} mpmc_queue_t;
static inline void __mpmc_init(mpmc_queue_t *q, mpmc_cell_t *buffer, uint32_t cap) {
    q->buffer = buffer;
    q->mask = cap - 1;
    atomic_store(&q->head, 0);
    atomic_store(&q->tail, 0);
    for (uint32_t i = 0; i < cap; i++) {
        atomic_store(&buffer[i].seq, i);
        buffer[i].data = NULL;
    }
}
static inline bool __mpmc_push(mpmc_queue_t *q, void *item) {
    mpmc_cell_t *cell;
    uint32_t pos;
    for (;;) {
        pos = atomic_load_explicit(&q->tail, memory_order_relaxed);
        cell = &q->buffer[pos & q->mask];
        uint32_t seq = atomic_load_explicit(&cell->seq, memory_order_acquire);
        int32_t diff = (int32_t)seq - (int32_t)pos;
        if (diff == 0) {
            if (atomic_compare_exchange_weak_explicit(&q->tail, &pos, pos + 1, memory_order_relaxed, memory_order_relaxed))
                break;
        } else if (diff < 0) {
            return false; // full
        }
    }
    cell->data = item;
    atomic_store_explicit(&cell->seq, pos + 1, memory_order_release);
    return true;
}
static inline void *__mpmc_pop(mpmc_queue_t *q) {
    mpmc_cell_t *cell;
    uint32_t pos;
    for (;;) {
        pos = atomic_load_explicit(&q->head, memory_order_relaxed);
        cell = &q->buffer[pos & q->mask];
        uint32_t seq = atomic_load_explicit(&cell->seq, memory_order_acquire);
        int32_t diff = (int32_t)seq - (int32_t)(pos + 1);
        if (diff == 0) {
            if (atomic_compare_exchange_weak_explicit(&q->head, &pos, pos + 1, memory_order_relaxed, memory_order_relaxed))
                break;
        } else if (diff < 0) {
            return NULL; // empty
        }
    }
    void *item = cell->data;
    atomic_store_explicit(&cell->seq, pos + q->mask + 1, memory_order_release);
    return item;
}

#define DEFINE_QUEUE_TYPE(type, name, CAP)                  \
                                                            \
STATIC_ASSERT(IS_POWER_OF_TWO(CAP), size_NOT_power_of_two); \
                                                            \
typedef struct {                                            \
    mpmc_queue_t core;                                      \
    mpmc_cell_t buffer[CAP];                                \
} name##_t;                                                 \
                                                            \
static inline void name##_init(name##_t *q) {               \
    __mpmc_init(&q->core, q->buffer, CAP);                  \
}                                                           \
                                                            \
static inline int name##_push(name##_t *q, type *item) {    \
    return __mpmc_push(&q->core, item);                     \
}                                                           \
                                                            \
static inline type *name##_pop(name##_t *q) {               \
    return (type *)__mpmc_pop(&q->core);                    \
}
/*-------------------------------*/

#ifdef __cplusplus
}
#endif
#endif
