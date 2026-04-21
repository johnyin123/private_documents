#include <fcgiapp.h>
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <stdlib.h>
#include <ctype.h>
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
#define _ITEM(c, n)   [c] = #n,
    static const char *method_map[] = { S_METHOD(_ITEM) };
    static const int method_map_len = ARRAY_LEN(method_map);
    #define METHOD_STR(c) code2str((c), method_map, method_map_len, "NONE")
    static const char *mime_type[] = { S_MIME_TYPE(_ITEM) };
    static const int mime_type_len = ARRAY_LEN(mime_type);
    #define MIME_STR(c)   code2str((c), mime_type, mime_type_len, "application/octet-stream")
#undef _ITEM
static inline const char *code2str(const uint16_t code, const char *tbl[], const size_t len, const char *nodef) {
    if(code<len) {
        const char *s = tbl[code];
        if(s) return s;
    }
    return nodef;
}
static inline enum method_t http_method(const char *m, size_t len) {
    for(int i=0;i<method_map_len;i++) {
        const char *s = METHOD_STR(i);
        if(strlen(s)==len && memcmp(m, s, len)==0) return i;
    }
    return METHOD_NONE;
}
static inline const char* req_get_header(FCGX_Request *r, const char *key) {
    return FCGX_GetParam(key, r->envp);
}
static inline const char* req_method(FCGX_Request *r) {
    return req_get_header(r, "REQUEST_METHOD");
}
static inline const char* req_uri(FCGX_Request *r) {
    return req_get_header(r, "DOCUMENT_URI");
}
static inline const char* req_query(FCGX_Request *r) {
    return req_get_header(r, "QUERY_STRING");
}
static inline const char* req_cookie(FCGX_Request *r) {
    return req_get_header(r, "HTTP_COOKIE");
}
static inline int req_content_length(FCGX_Request *r) {
    const char *len_str = req_get_header(r, "CONTENT_LENGTH");
    return len_str ? atoi(len_str) : 0;
}
static inline bool query_get(const char *qs, const char *key, char *out, size_t out_sz) {
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
static inline void url_decode(char *s) {
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
static inline void make_response(FCGX_Request *req, uint16_t status, enum mime_t mime, const char *format, ...) {
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
void dump_fcgx_request(FCGX_Request *req) {
    fprintf(stderr, "=== FCGX_Request Dump ===\n");
    fprintf(stderr, "    requestId: %d\n", req->requestId);
    fprintf(stderr, "    role: %d\n", req->role);
    fprintf(stderr, "    ipcFd: %d\n", req->ipcFd);
    fprintf(stderr, "    isBeginProcessed: %d\n", req->isBeginProcessed);
    fprintf(stderr, "    keepConnection: %d\n", req->keepConnection);
    fprintf(stderr, "    appStatus: %d\n", req->appStatus);
    fprintf(stderr, "    nWriters: %d\n", req->nWriters);
    fprintf(stderr, "    flags: %d\n", req->flags);
    fprintf(stderr, "    listen_sock: %d\n", req->listen_sock);
    fprintf(stderr, "--- Environment Variables ---\n");
    if (req->envp) {
        for(char **env = req->envp; *env; env++) fprintf(stderr, "    %s\n", *env);
    }
    // Stream pointers
    fprintf(stderr, "--- Streams ---\n");
    fprintf(stderr, "    in:  %p\n", (void*)req->in);
    fprintf(stderr, "    out: %p\n", (void*)req->out);
    fprintf(stderr, "    err: %p\n", (void*)req->err);
}

int main(int argc, char *argv[]) {
    UNUSED(argc);UNUSED(argv);
    if (FCGX_Init() != 0) {
        fprintf(stderr, "FCGX_Init failed\n");
        return 1;
    }
    int backlog = 8;
    int sock = FCGX_OpenSocket("localhost:9999", backlog);
    if (sock < 0) {
        perror("FCGX_OpenSocket");
        return 1;
    }
    FCGX_Request request;
    if (FCGX_InitRequest(&request, sock, 0) != 0) {
        fprintf(stderr, "FCGX_InitRequest failed\n");
        return 1;
    }
    for(;;) {
        int rc = FCGX_Accept_r(&request);
        if (rc < 0) {
            fprintf(stderr, "Accept failed: %d\n", rc);
            break;
        }
        const char *host = req_get_header(&request, "FN_HANDLER");
        const char *method = req_method(&request);
        const char *uri = req_uri(&request);
        char buf[BUF_SIZE] = {0}; /* POST DATA */
        if((rc=req_body(&request, buf, sizeof(buf)))>0) {
            buf[rc] = '\0';
            fprintf(stderr, "POST SIZE = %d, %s\n", rc, buf);
        }
        make_response(&request, 202, MIME_JSON, "{ \"key\":\"Hello, %s %s %s FastCGI\" }", host ? host : "(null)", method ? method : "(null)", uri ? uri : "(null)");
        //usleep(1000*1000*4);
        dump_fcgx_request(&request);
        FCGX_Finish_r(&request);
    }
    return 0;
}
/*
# sudo apt install autoconf automake libtool
# git clone https://github.com/FastCGI-Archives/fcgi2.git
limit_conn_zone $server_name zone=connperserver:10m;
server {
    listen 127.0.0.1:19999;
    server_name _;
    error_page 403 = @403;
    location @403 { return 403 '{"code":403,"name":"lberr","desc":"Resource Forbidden"}'; }
    error_page 405 = @405;
    location @405 { return 405 '{"code":405,"name":"lberr","desc":"Method not allowed"}'; }
    location / {
        limit_conn connperserver 1;
        limit_conn_status 403;
        if ($request_method !~ ^(GET|HEAD)$) { return 405; }
        include /etc/nginx/fastcgi_params;
        fastcgi_param YOURENV Profile;
        fastcgi_pass 127.0.0.1:9999;
    }
}
*/
