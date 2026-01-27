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
#if defined(__WIN32__)
    #include <winsock2.h>
    #define SHUT_WR SD_SEND
#else
    #include <sys/socket.h>
#endif

struct query_t {
    char val[24];
};
struct header_property_t {
    char key[32];
    char value[128];
};
struct request_t {
    char method[8];
    char protocol[12];
    char url[128];
    size_t nquery; /* number of queries */
    struct query_t query[8];
    int content_length;
};
enum mime_t { JSON = 0, PLAIN_TEXT };
struct response_t {
    unsigned int status;
    enum mime_t mime;
    size_t body_len;
    time_t time;
    char* body;
};
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
#include <string.h>
#include <ctype.h>
#include <stdlib.h>
#include <stdio.h>

#define UNUSED(arg)            ((void)arg)
#define SRV_INFO               "Server: inner"
#define method_append(r, c)    str_append(r->method, sizeof(r->method)-1, c)
#define protocol_append(r, c)  str_append(r->protocol, sizeof(r->protocol)-1, c)
#define url_append(r, c)       str_append(r->url, sizeof(r->url)-1, c)
#define append(s, len, c)      str_append(s, len, c)
static inline int str_append(char *str, size_t len, char c) {
    size_t l = strlen(str);
    if (l < len) {
        str[l] = c;
        return 0;
    }
    return -1;
}
static inline int query_append(struct request_t* r, char c) {
    if (r->nquery >= sizeof(r->query) / sizeof(struct query_t))
        return -1;
    return str_append(r->query[r->nquery].val, sizeof(r->query[r->nquery].val)-1, c);
}
static inline int query_next(struct request_t* r) {
    if (r->nquery >= sizeof(r->query) / sizeof(struct query_t))
        return -1;
    r->nquery++;
    return 0;
}
static inline void clear_header_property(struct header_property_t* prop) {
    memset(prop->key, 0, sizeof(prop->key));
    memset(prop->value, 0, sizeof(prop->value));
}
static inline int parse(int sock, struct request_t* r, int *read_len)
{
    int state = 0; /* state machine */
    int read_next = 1; /* indicator to read data */
    char c = 0; /* current character */
    char buffer[16]; /* receive buffer */
    int buffer_index = sizeof(buffer); /* index within the buffer */
    int content_length = -1; /* used only in POST requests */
    struct header_property_t prop; /* temporary space to hold header key/value properties*/
    memset(r, 0, sizeof(struct request_t));
    clear_header_property(&prop);
    *read_len = 0;
    while (sock >= 0) {
        /* read data */
        if (read_next) {
            /* read new data, buffers at a time */
            if (buffer_index >= (int)sizeof(buffer)) {
                memset(buffer, 0, sizeof(buffer));
                int rc = recv(sock, buffer, sizeof(buffer), 0);
                if (rc < 0)
                    return -99; /* read error */
                if (rc == 0)
                    return 0; /* no data read */
                *read_len += rc;
                buffer_index = 0;
            }
            c = buffer[buffer_index];
            ++buffer_index;
            /* state management */
            read_next = 0;
        }
        /* execute state machine */
        switch (state) {
            case 0: /* kill leading spaces */
                if (isspace(c)) {
                    read_next = 1;
                } else {
                    state = 1;
                }
                break;
            case 1: /* method */
                if (isspace(c)) {
                    state = 2;
                } else {
                    if (method_append(r, c))
                        return -state;
                    read_next = 1;
                }
                break;
            case 2: /* kill spaces */
                if (isspace(c)) {
                    read_next = 1;
                } else {
                    state = 3;
                }
                break;
            case 3: /* url */
                if (isspace(c)) {
                    state = 5;
                } else if (c == '?') {
                    read_next = 1;
                    state = 4;
                } else {
                    if (url_append(r, c))
                        return -state;
                    read_next = 1;
                }
                break;
            case 4: /* queries */
                if (isspace(c)) {
                    if (query_next(r))
                        return -state;
                    state = 5;
                } else if (c == '&') {
                    if (query_next(r))
                        return -state;
                    read_next = 1;
                } else {
                    if (query_append(r, c))
                        return -state;
                    read_next = 1;
                }
                break;
            case 5: /* kill spaces */
                if (isspace(c)) {
                    read_next = 1;
                } else {
                    state = 6;
                }
                break;
            case 6: /* protocol */
                if (isspace(c)) {
                    state = 7;
                } else {
                    if (protocol_append(r, c))
                        return -state;
                    read_next = 1;
                }
                break;
            case 7: /* kill spaces */
                if (isspace(c)) {
                    read_next = 1;
                } else {
                    clear_header_property(&prop);
                    state = 8;
                }
                break;
            case 8: /* header line key */
                if (c == ':') {
                    state = 9;
                    read_next = 1;
                } else {
                    if (append(prop.key, sizeof(prop.key)-1, c))
                        return -state;
                    read_next = 1;
                }
                break;
            case 9: /* kill spaces */
                if (isspace(c)) {
                    read_next = 1;
                } else {
                    state = 10;
                }
                break;
            case 10: /* header line value */
                if (c == '\r') {
                    if (strcmp("Content-Length", prop.key) == 0)
                        content_length = strtol(prop.value, 0, 0);
                    clear_header_property(&prop);
                    state = 11;
                    read_next = 1;
                } else {
                    if (append(prop.value, sizeof(prop.value)-1, c))
                        return -state;
                    read_next = 1;
                }
                break;
            case 11:
                if (c == '\n') {
                    read_next = 1;
                } else if (c == '\r') {
                    state = 12;
                    read_next = 1;
                } else {
                    state = 8;
                }
                break;
            case 12: /* end of header */
                if (c == '\n') {
                    if (content_length > 0) {
                        state = 13;
                        read_next = 1;
                    } else {
                        return 0; /* end of header, no content => end of request */
                    }
                } else {
                    state = 8;
                }
                break;
            case 13: /* content (POST queries) */
                if (c == '&') {
                    if (query_next(r))
                        return -state;
                    read_next = 1;
                } else if (c == '\r') {
                    if (query_next(r))
                        return -state;
                    read_next = 1;
                } else if (c == '\n') {
                    read_next = 1;
                } else if (c == '\0') {
                    if (query_next(r))
                        return -state;
                    return 0; /* end of content */
                } else {
                    if (query_append(r, c))
                        return -state;
                    read_next = 1;
                }
                break;
        }
    }
    return -99;
}

static inline int send_response(int sock, const struct request_t *req, struct response_t *res)
{
    UNUSED(req);
    char dest[4096], date_line[64];
    size_t dest_len = sizeof(dest);
    strftime(date_line, sizeof(date_line), "Date: %a, %d %b %Y %H:%M:%S GMT", gmtime(&(res->time)));
    int len = snprintf(dest, dest_len, "HTTP/1.1 %s\r\n%s\r\nContent-Type: %s\r\nContent-Length: %zu\r\n%s\r\n\r\n"
        "%.*s",
        status_str(res->status),
        date_line,
        mime_str(res->mime),
        res->body_len,
        SRV_INFO,
        (int)res->body_len,
        res->body);
    return (send(sock, dest, len, 0) == len) ? 0 : -1;
}
static inline void dump_request(const struct request_t* req ) {
    debugln("METHOD :%s", req->method);
    debugln("PROTO  :%s", req->protocol);
    debugln("URL    :%s", req->url);
    for(int i=0;i<req->nquery;i++) debugln("QUERY  :%s", req->query[i].val);
}
#ifdef __cplusplus
}
#endif
#endif
