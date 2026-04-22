#include "fcgi_utils.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <ctype.h>

struct env g_env = {
    .trace_level = 0,
};

#define _ITEM(c, n)   [c] = #n,
static const char *method_map[] = { S_METHOD(_ITEM) };
static const int method_map_len = ARRAY_LEN(method_map);
#define METHOD_STR(c) code2str((c), method_map, method_map_len, "NONE")
static const char *mime_type[] = { S_MIME_TYPE(_ITEM) };
static const int mime_type_len = ARRAY_LEN(mime_type);
#define MIME_STR(c)   code2str((c), mime_type, mime_type_len, "application/octet-stream")
#undef _ITEM
const char *code2str(const uint16_t code, const char *tbl[], const size_t len, const char *nodef) {
    if(code<len) {
        const char *s = tbl[code];
        if(s) return s;
    }
    return nodef;
}
enum method_t http_method(const char *m, size_t len) {
    for(int i=0;i<method_map_len;i++) {
        const char *s = METHOD_STR(i);
        if(strlen(s)==len && memcmp(m, s, len)==0) return i;
    }
    return METHOD_NONE;
}
const char* req_get_header(FCGX_Request *r, const char *key) {
    return FCGX_GetParam(key, r->envp);
}
const char* req_method(FCGX_Request *r) {
    return req_get_header(r, "REQUEST_METHOD");
}
const char* req_uri(FCGX_Request *r) {
    return req_get_header(r, "DOCUMENT_URI");
}
const char* req_query(FCGX_Request *r) {
    return req_get_header(r, "QUERY_STRING");
}
const char* req_cookie(FCGX_Request *r) {
    return req_get_header(r, "HTTP_COOKIE");
}
int req_content_length(FCGX_Request *r) {
    const char *len_str = req_get_header(r, "CONTENT_LENGTH");
    return len_str ? atoi(len_str) : 0;
}
bool query_get(const char *qs, const char *key, char *out, size_t out_sz) {
    if (!qs || !key || !out || out_sz == 0) return false;
    size_t key_len = strlen(key);
    const char *p = qs;
    while (*p) {
        if (strncmp(p, key, key_len) == 0 && p[key_len] == '=') {
            const char *val = p + key_len + 1;
            size_t i = 0;
            while (val[i] && val[i] != '&' && i < out_sz - 1) {
                out[i] = val[i];
                i++;
            }
            out[i] = '\0';
            return true;
        }
        while (*p && *p != '&') p++;
        if (*p == '&') p++;
    }
    return false;
}
static inline int hex(char c) {
    if ('0'<=c && c<='9') return c-'0';
    if ('a'<=c && c<='f') return c-'a'+10;
    if ('A'<=c && c<='F') return c-'A'+10;
    return -1;
}
void url_decode(char *s) {
    char *dst = s;
    while(*s) {
        if (*s == '%' &&
            isxdigit((unsigned char)s[1]) &&
            isxdigit((unsigned char)s[2])) {
            int hi = hex(s[1]);
            int lo = hex(s[2]);
            *dst++ = (char)((hi << 4) | lo);
            s += 3;
        } else if (*s == '+') {
            *dst++ = ' ';
            s++;
        } else {
            *dst++ = *s++;
        }
    }
    *dst = '\0';
}
int req_body(FCGX_Request *req, char *out, size_t out_len) {
    int len = req_content_length(req);
    if(len<=0||len>(int)out_len) return -1;
    return FCGX_GetStr(out, out_len, req->in);
}
void make_response(FCGX_Request *req, uint16_t status, enum mime_t mime, const char *format, ...) {
    va_list args;
    char json_str[BUF_SIZE]={0};
    va_start(args, format);
    int ret = vsnprintf(json_str, sizeof(json_str), format, args);
    va_end(args);
    if(ret < 0) return;
    size_t len = strlen(json_str);
    FCGX_FPrintF(req->out, "Status: %d\r\n"
        "%s\r\nContent-Type: %s\r\nContent-Length: %d\r\n"
        "\r\n"
        "%s", status, SRV_INFO, MIME_STR(mime), len, json_str);
}
int get_cmd_output(const char* cmd, char *buf, size_t buf_len) {
    FILE* pipe = popen(cmd, "r");
    if (!pipe) { buf[0] = '\0'; return EXIT_FAILURE; }
    size_t n = fread(buf, 1, buf_len - 1, pipe);
    if (ferror(pipe)) {
        fclose(pipe);
        buf[0] = '\0';
        return EXIT_FAILURE;
    }
    pclose(pipe);
    buf[n] = '\0';
    return EXIT_SUCCESS;
}
/*-------------------------------*/
void queue_init(struct queue_t *q, void *elems, size_t size) {
    memset(q, 0, sizeof(*q));
    q->elems = elems;
    q->cap = size;
    pthread_mutex_init(&q->mutex, NULL);
    pthread_cond_init(&q->not_empty, NULL);
    pthread_cond_init(&q->not_full, NULL);
}
void queue_stop(struct queue_t *q) {
    q->stop=true;
    pthread_mutex_lock(&q->mutex);
    pthread_cond_broadcast(&q->not_empty);
    pthread_cond_broadcast(&q->not_full);
    pthread_mutex_unlock(&q->mutex);
}
void queue_destroy(struct queue_t *q) {
    pthread_mutex_destroy(&q->mutex);
    pthread_cond_destroy(&q->not_empty);
    pthread_cond_destroy(&q->not_full);
}
int queue_push(struct queue_t *q, void *elem) {
    pthread_mutex_lock(&q->mutex);
    while (q->count >= q->cap && !q->stop) {
        pthread_cond_wait(&q->not_full, &q->mutex);
    }
    if (q->stop) {
        pthread_mutex_unlock(&q->mutex);
        return EXIT_FAILURE;
    }
    q->elems[q->tail] = elem;
    q->tail = (q->tail + 1) % q->cap;
    q->count++;
    pthread_cond_signal(&q->not_empty);
    pthread_mutex_unlock(&q->mutex);
    return EXIT_SUCCESS;
}
void *queue_pop(struct queue_t *q) {
    pthread_mutex_lock(&q->mutex);
    while (q->count == 0 && !q->stop) {
        pthread_cond_wait(&q->not_empty, &q->mutex);
    }
    if (q->stop && q->count == 0) {
        pthread_mutex_unlock(&q->mutex);
        return NULL;
    }
    void *elem = q->elems[q->head];
    q->head = (q->head + 1) % q->cap;
    q->count--;
    pthread_cond_signal(&q->not_full);
    pthread_mutex_unlock(&q->mutex);
    return elem;
}
