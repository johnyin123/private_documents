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
    #include <ws2tcpip.h>
    #define SHUT_RD   SD_RECEIVE
    #define SHUT_WR   SD_SEND
    #define SHUT_RDWR SD_BOTH
    #define close_socket closesocket
#else
    #include <sys/socket.h>
    #include <unistd.h>
    #define recv(a,b,c,d) read(a,b,c)
    #define send(a,b,c,d) write(a,b,c)
    #define close_socket close
#endif

#define MAX_METHOD   8
#define MAX_PROTO    12
#define MAX_URL      128
#define MAX_HEADERS  8
#define MAX_QUERIES  8
#define MAX_PAYLOAD  4096

struct query_t {
    char val[24];
};
struct hdr_prop_t {
    char key[32];
    char val[128];
};
struct request_t {
    char method[MAX_METHOD];
    char protocol[MAX_PROTO];
    char url[MAX_URL];
    size_t nprop;
    struct hdr_prop_t prop[MAX_HEADERS];
    size_t nquery;
    struct query_t query[MAX_QUERIES];
    int content_length;
    char payload[MAX_PAYLOAD];
};
#include <stddef.h>

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
/*fix Signed char issue*/
#define IS_SPACE(c) isspace((unsigned char)(c))
#define IS_ALNUM(c) isalnum((unsigned char)(c))
#define IS_DIGIT(c) isdigit((unsigned char)(c))
#define TO_LOWER(c) tolower((unsigned char)(c))
#include <stdlib.h>
#include <stdio.h>

#define UNUSED(arg)            ((void)arg)
#define SRV_INFO               "Server: inner"
#define method_append(r, c)    str_append(r->method, sizeof(r->method)-1, c)
#define protocol_append(r, c)  str_append(r->protocol, sizeof(r->protocol)-1, c)
#define url_append(r, c)       str_append(r->url, sizeof(r->url)-1, c)
#define append(s, len, c)      str_append(s, len, c)
static inline int str_append(char *str, size_t max, char c) {
    unsigned char uc = (unsigned char)c;
    size_t l = strlen(str);
    if (l + 1 >= max) return -1;
    str[l] = uc;       // store as byte
    str[l + 1] = '\0';
    return 0;
}
static inline int prop_append_key(struct request_t* r, char c) {
    if (r->nprop >= sizeof(r->prop) / sizeof(struct hdr_prop_t))
        return -1;
    return str_append(r->prop[r->nprop].key, sizeof(r->prop[r->nprop].key)-1, c);
}
static inline int prop_append_val(struct request_t* r, char c) {
    if (r->nprop >= sizeof(r->prop) / sizeof(struct hdr_prop_t))
        return -1;
    return str_append(r->prop[r->nprop].val, sizeof(r->prop[r->nprop].val)-1, c);
}
static inline int prop_next(struct request_t* r) {
    if (r->nprop >= sizeof(r->prop) / sizeof(struct hdr_prop_t))
        return -1;
    r->nprop++;
    return 0;
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
enum parse_state_t {
    ST_START = 0,
    ST_METHOD,
    ST_METHOD_WS,
    ST_URL,
    ST_QUERY,
    ST_URL_WS,
    ST_PROTO,
    ST_HDR_WS,
    ST_HDR_KEY,
    ST_HDR_VAL_WS,
    ST_HDR_VAL,
    ST_HDR_CR,        // saw '\r' after header value
    ST_HDR_LF,        // saw '\n' after '\r'
    ST_HDR_END_CR,    // saw '\r' on empty line
    ST_HDR_END_LF,    // saw '\n' -> end of headers
    ST_BODY
};

static inline const char* get_state_info(int state) {
    const char* const state_info[] = {
        "state START",
        "state METHOD",
        "state METHOD SPACE",
        "state URL",
        "state QUERY",
        "state URL SPACE",
        "state PROTO",
        "state HDR SPACE",
        "state HEADER KEY",
        "state HEADER VALUE SPACE",
        "state HEADER VALUE",
        "state ST_HDR_CR",
        "state ST_HDR_LF",
        "state ST_HDR_END_CR",
        "state ST_HDR_END_LF",
        "state BODY"
    };
    if (state >= ST_START && state <= ST_BODY)
        return state_info[state];
    return "state UNKNOWN";
}
static inline int parse(int sock, struct request_t* r, int *read_len) {
    int body_read = 0; /* used only in POST requests */
    enum parse_state_t state = ST_START; /* state machine */
    int read_next = 1;
    char buf[MAX_PAYLOAD];    /* receive buf */
    int buf_pos = 0;   /* current read position */
    char c = 0;        /* current character */
    memset(r, 0, sizeof(*r));
    *read_len = 0;
    /* only recv once */
    int rc = recv(sock, buf, sizeof(buf), 0);
    if (rc < 0)
        return -99; /* read error */
    if (rc == 0)
        return 0; /* no data read */
    *read_len = rc;
    for(;;) {
        /* read data */
        if (read_next) {
            if(buf_pos > rc - 1)
                return 0;
            c = buf[buf_pos++];
            /* state management */
            read_next = 0;
        }
        /* execute state machine */
        switch (state) {
            case ST_START: /* eat leading spaces */
                if (IS_SPACE(c)) {
                    read_next = 1;
                } else {
                    state = ST_METHOD;
                }
                break;
            case ST_METHOD: /* method */
                if (IS_SPACE(c)) {
                    state = ST_METHOD_WS;
                } else {
                    if (method_append(r, c))
                        return -state;
                    read_next = 1;
                }
                break;
            case ST_METHOD_WS: /* eat spaces */
                if (IS_SPACE(c)) {
                    read_next = 1;
                } else {
                    state = ST_URL;
                }
                break;
            case ST_URL: /* url */
                if ((unsigned char)c < 0x20 || (unsigned char)c > 0x7E) {
                    return -state;  /* invalid char in URL */
                }
                if (IS_SPACE(c)) {
                    state = ST_URL_WS;
                } else if (c == '?') {
                    read_next = 1;
                    state = ST_QUERY;
                } else {
                    if (url_append(r, c))
                        return -state;
                    read_next = 1;
                }
                break;
            case ST_QUERY: /* queries */
                if (IS_SPACE(c)) {
                    if (query_next(r))
                        return -state;
                    state = ST_URL_WS;
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
            case ST_URL_WS: /* eat spaces */
                if (IS_SPACE(c)) {
                    read_next = 1;
                } else {
                    state = ST_PROTO;
                }
                break;
            case ST_PROTO: /* protocol */
                if (IS_SPACE(c)) {
                    state = ST_HDR_WS;
                } else {
                    if (protocol_append(r, c))
                        return -state;
                    read_next = 1;
                }
                break;
            case ST_HDR_WS: /* eat spaces */
                if (IS_SPACE(c)) {
                    read_next = 1;
                } else {
                    state = ST_HDR_KEY;
                }
                break;
            case ST_HDR_KEY: /* header line key */
                if (c == ':') {
                    state = ST_HDR_VAL_WS;
                    read_next = 1;
                } else if (c == '\r' || c == '\n') {
                    return -state;
                } else {
                    if (prop_append_key(r, c))
                        return -state;
                    read_next = 1;
                }
                break;
            case ST_HDR_VAL_WS: /* eat spaces */
                if (IS_SPACE(c)) {
                    read_next = 1;
                } else {
                    state = ST_HDR_VAL;
                }
                break;
            case ST_HDR_VAL: /* header line value */
                if (c == '\r') {
                    if (strcasecmp("Content-Length", r->prop[r->nprop].key) == 0) {
                        long v = strtol(r->prop[r->nprop].val, 0, 0);
                        if (v < 0 || v > MAX_PAYLOAD) return -state;
                        r->content_length = (int)v;
                    }
                    if (prop_next(r))
                        return -state;
                    state = ST_HDR_CR;
                    read_next = 1;
                } else {
                    if (prop_append_val(r, c))
                        return -state;
                    read_next = 1;
                }
                break;
            case ST_HDR_CR:
                if (c != '\n')
                    return -state;
                state = ST_HDR_LF;
                read_next = 1;
                break;
            case ST_HDR_LF:
                if (c == '\r') {
                    state = ST_HDR_END_CR;   // empty line
                    read_next = 1;
                } else {
                    state = ST_HDR_KEY;      // next header
                    read_next = 0;    // reprocess c as header key
                }
                break;
            case ST_HDR_END_CR:
                if (c != '\n')
                    return -state;
                state = ST_HDR_END_LF;
                read_next = 1;
                break;
            case ST_HDR_END_LF:
                if (r->content_length > 0) {
                    state = ST_BODY;
                    /* DO NOT force recv here */
                } else {
                    return 0;   // request complete
                }
                break;
            case ST_BODY: /* content (POST queries) */
                r->payload[body_read++] = c;
                r->payload[body_read] = '\0';
                if (body_read >= r->content_length) {
                    return 0;
                }
                read_next = 1;
                break;
        }
    }
    return -99;
}
static inline int send_response(int sock, const struct request_t *req, struct response_t *res) {
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
    debugln("NQUERY :%lu", req->nquery);
    for(int i=0;i<req->nquery;i++) debugln("QUERY  :%s", req->query[i].val);
    debugln("NPROP  :%lu", req->nprop);
    for(int i=0;i<req->nprop;i++) debugln("PROP   :%s: %s", req->prop[i].key, req->prop[i].val);
    if(req->content_length) debugln("PAYLOAD[%d]:%s", req->content_length, req->payload);
}
#ifdef __cplusplus
}
#endif
#endif
/*
# Body arrives in same packet as headers
printf "GET / HTTP/1.1\r\n\r\n" | nc 127.0.0.1 8080
printf "GET /index.html HTTP/1.1\r\nHost: example.com\r\nUser-Agent: nc\r\n\r\n" | nc 127.0.0.1 8080
printf "GET / HTTP/1.1\r" | nc 127.0.0.1 8080
printf "POST /test HTTP/1.1\r\nContent-Length: 5\r\n\r\nhello" | nc 127.0.0.1 8080
(echo -n "POST /test HTTP/1.1\r\nContent-Length: 5\r\n\r\n"; sleep 1; echo -n "hello") | nc 127.0.0.1 8080
# Header without colon
printf "GET / HTTP/1.1\r\nBadHeader\r\n\r\n" | nc 127.0.0.1 8080
# Signed char issue
printf "GET /\xff HTTP/1.1\r\n\r\n" | nc 127.0.0.1 8080
*/
