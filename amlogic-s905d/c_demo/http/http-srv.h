#ifndef __PARSER_H_103833_538735893__INC__
#define __PARSER_H_103833_538735893__INC__
#ifdef __cplusplus
extern "C" {
#endif

#ifdef DEBUG
    #include <stdio.h>
    #define debugln(...) fprintf(stderr, __VA_ARGS__)
#else
    #define debugln(...) do {} while (0)
#endif

#include <stddef.h>
#include <time.h>

#define MAX_REQUEST_LEN 0x400

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

#define SRV_INFO "Server: inner"
static inline enum method_t http_method(const char *req) {
    if (!req) return UNKNOWN;
    if (memcmp(req, "GET ", 4) == 0)
        return GET;
    if (memcmp(req, "POST ", 5) == 0)
        return POST;
    return UNKNOWN;
}
static inline const char *http_body(const char *req) {
    if (!req) return NULL;
    const char *p = strstr(req, "\r\n\r\n");
    if (p) return p + 4;
    p = strstr(req, "\n\n");
    if (p) return p + 2;
    return NULL;
}
static inline const char *http_uri(const char *req) {
    if (!req) return NULL;
    const char *sp1 = strchr(req, ' ');
    if (!sp1) return NULL;
    const char *sp2 = strchr(sp1 + 1, ' ');
    if (!sp2) return NULL;
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
static inline int createResponse(struct response_t response, char* dest, size_t destLen) {
    char dateLine[64];
    strftime(dateLine, sizeof(dateLine), "Date: %a, %d %b %Y %H:%M:%S GMT", gmtime(&(response.time)));
    return snprintf(dest, destLen, "HTTP/1.1 %s\r\n%s\r\nContent-Type: %s\r\nContent-Length: %zu\r\n%s\r\n\r\n%s",
        status_str(response.status),
        dateLine,
        mime_str(response.mime),
        response.body_len,
        SRV_INFO,
        response.body);
}

#ifdef __cplusplus
}
#endif
#endif
