#ifndef __PARSER_H_103833_538735893__INC__
#define __PARSER_H_103833_538735893__INC__
#ifdef __cplusplus
extern "C" {
#endif

#ifdef DEBUG
    #include <stdio.h>
    #define debugln(format,args...) fprintf(stderr, "%s:%d == "format"\n", __FILE__, __LINE__, ##args) /*#define debugln(...)           fprintf(stderr, __VA_ARGS__)*/
#else
    #define debugln(...) do {} while (0)
#endif

#include <stddef.h>
#include <time.h>

enum method_t { UNKNOWN = 0, GET, POST };
enum mime_t { JSON = 0, PLAIN_TEXT };
struct response_t {
    unsigned int status;
    enum mime_t mime;
    size_t body_len;
    time_t time;
    char* body;
};

#include <stdio.h>
#include <string.h>
#if defined(_WIN32)
void *memmem(const void *haystack, size_t hlen, const void *needle, size_t nlen) {
    if (nlen == 0) return (void *)haystack;
    if (hlen < nlen) return NULL;
    const unsigned char *h = (const unsigned char *)haystack;
    const unsigned char *n = (const unsigned char *)needle;
    for (size_t i = 0; i <= hlen - nlen; i++) {
        if (h[i] == n[0] && memcmp(h + i, n, nlen) == 0) {
            return (void *)(h + i);
        }
    }
    return NULL;
}
#endif

#define SRV_INFO "Server: inner"
static inline enum method_t http_method(const char *req, ssize_t req_len) {
    // if (sscanf(buffer, "%15s %2047s %15s", method, uri, version) != 3) return -1;
    if (!req) return UNKNOWN;
    if (memcmp(req, "GET ", 4) == 0 && req_len > 4)
        return GET;
    if (memcmp(req, "POST ", 5) == 0 && req_len > 5)
        return POST;
    return UNKNOWN;
}
static inline const char *http_body(const char *req, ssize_t req_len, size_t* body_len) {
    if (!req) return NULL;
    const char *p = memmem(req, req_len, "\r\n\r\n", 4);
    if (!p) return NULL;
    *body_len = req_len - ((p - req) + 4);
    if (*body_len > 0)
        return p + 4;
    return NULL;
}
static inline const char *http_uri(const char *req, ssize_t req_len, size_t* path_len) {
    if (!req) return NULL;
    const char *sp1 = memchr(req, ' ', req_len);
    if (!sp1) return NULL;
    req_len -= ((sp1 - req) + 1);
    const char *sp2 = memchr(sp1 + 1, ' ', req_len);
    if (!sp2) return NULL;
    *path_len = sp2 - sp1 - 1;
    return sp1 + 1;
}
static inline const char *mime_str(enum mime_t m) {
    switch (m) {
        case JSON:       return "application/json";
        case PLAIN_TEXT: return "text/plain; charset=utf-8";
        default:         return "application/octet-stream";
    }
}
static inline const char *status_str(unsigned int s) {
    switch (s) {
        case 200: return "200 OK";
        case 403: return "403 Forbidden";
        case 404: return "404 Not Found";
        default:  return "500 Internal Server Error";
    }
}
static inline int make_response(struct response_t *res, char* dest, size_t dest_len) {
    char date_line[64];
    strftime(date_line, sizeof(date_line), "Date: %a, %d %b %Y %H:%M:%S GMT", gmtime(&(res->time)));
    return snprintf(dest, dest_len, "HTTP/1.1 %s\r\n%s\r\nContent-Type: %s\r\nContent-Length: %zu\r\n%s\r\n\r\n%s",
        status_str(res->status),
        date_line,
        mime_str(res->mime),
        res->body_len,
        SRV_INFO,
        res->body);
}

#ifdef __cplusplus
}
#endif
#endif
