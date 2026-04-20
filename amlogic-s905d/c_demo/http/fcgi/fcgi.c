#include <fcgiapp.h>
#include <stdio.h>
#include <stdbool.h>
#include <string.h>
#include <stdlib.h>
#include <ctype.h>
#define UNUSED(x)             ((void)(x))
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
    fprintf(stderr, "\n--- Environment Variables ---\n");
    if (req->envp) {
        for(char **env = req->envp; *env; env++) fprintf(stderr, "    %s\n", *env);
    }
    // Stream pointers
    fprintf(stderr, "\n--- Streams ---\n");
    fprintf(stderr, "    in:  %p\n", (void*)req->in);
    fprintf(stderr, "    out: %p\n", (void*)req->out);
    fprintf(stderr, "    err: %p\n", (void*)req->err);
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
        char buf[1024]; /* POST DATA */
        while(FCGX_GetStr(buf, sizeof(buf), request.in) > 0)
            ;
        FCGX_FPrintF(request.out, "Content-Type: text/plain\r\n\r\n");
        FCGX_FPrintF(request.out, "Hello, %s %s %s FastCGI\n", host ? host : "(null)", method ? method : "(null)", uri ? uri : "(null)");
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
