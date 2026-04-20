#include <fcgiapp.h>
#include <stdio.h>
#include <stdlib.h>
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
#include <unistd.h>
int main(int argc, char *argv[]) {
    UNUSED(argc);UNUSED(argv);
    if (FCGX_Init() != 0) {
        fprintf(stderr, "FCGX_Init failed\n");
        return 1;
    }
    int backlog = 8;
    int sock = FCGX_OpenSocket("127.0.0.1:9999", backlog);
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
