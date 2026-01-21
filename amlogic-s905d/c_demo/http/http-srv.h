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

// Only works with string literals
#define MATCHES(runtime_str, len, static_str)                   \
        ((runtime_str) != NULL &&                               \
         strnlen(runtime_str, len) == sizeof(static_str) - 1 && \
         strncmp((runtime_str), (static_str), sizeof(static_str) - 1) == 0)

enum t_http_method { UNKNOWN = 0, GET = 1, POST = 2 };
enum t_mime_type { JSON = 0, PLAIN_TEXT = 1 };
struct t_response {
    unsigned int status;
    enum t_mime_type mime;
    size_t bodyContentLen;
    time_t time;
    const char* body;
};

#include <stdio.h>
#include <string.h>

#define SRV_INFO "Server: inner"

static inline enum t_http_method getHttpMethod(const char* request) {
    const char* firstSpace = strchr(request, ' ');
    if (firstSpace == NULL) { return UNKNOWN; }
    const size_t len = (size_t)(firstSpace - request);
    if (MATCHES(request, len, "GET"))
        return GET;
    else if (MATCHES(request, len, "POST"))
        return POST;
    else
        return UNKNOWN;
}

static inline const char* getHttpBody(const char* request) {
    if (request == NULL) return NULL;
    // HTTP body starts after the first occurrence of \r\n\r\n
    const char* bodyStart = strstr(request, "\r\n\r\n");
    if (bodyStart != NULL) return bodyStart + 4;

    // Some non-standard implementations might use just \n\n
    bodyStart = strstr(request, "\n\n");
    if (bodyStart != NULL) return bodyStart + 2;

    return NULL;
}

static inline const char* getHttpUri(const char* request) {
    // Assume the URI will be the second space-delimited token
    char* dest = strchr(request, ' ');
    dest = strchr(dest, ' ');
    dest = dest + 1;
    return dest;
}

static inline void createResponse(struct t_response response, char* dest, size_t destLen) {
    const char* statusLine = "HTTP/1.1 500 Internal Server Error";
    switch (response.status) {
        case 200:
            statusLine = "HTTP/1.1 200 OK";
            break;
        case 403:
            statusLine = "HTTP/1.1 403 Forbidden";
            break;
    }
    const char* contentType = "application/octet-stream";
    switch (response.mime) {
        case JSON:
            contentType = "application/json";
            break;
        case PLAIN_TEXT:
            contentType = "text/plain; charset=UTF-8";
            break;
    }
    char dateLine[64];
    strftime(dateLine, sizeof(dateLine), "Date: %a, %d %b %Y %H:%M:%S GMT", gmtime(&(response.time)));
    snprintf(dest, destLen, "%s\r\n%s\r\nContent-Type: %s\r\nContent-Length: %zu\r\n%s\r\n\r\n%s",
        statusLine,
        dateLine,
        contentType,
        response.bodyContentLen,
        SRV_INFO,
        response.body);
}

#ifdef __cplusplus
}
#endif
#endif
