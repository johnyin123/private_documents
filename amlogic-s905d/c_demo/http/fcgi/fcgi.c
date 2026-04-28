#include "fcgi_utils.h"
#include <stdio.h>
#include <stdlib.h>
#define DEF_ADDR   "localhost:9999"

struct act_t {
    const enum method_t method;
    size_t uri_len;
    const char *s_uri;
    void  (*on_resp)(FCGX_Request *req);
};
static inline const struct act_t *find_action(const enum method_t method, const char *s_uri) {
    extern const int g_acts_len;
    extern const struct act_t g_acts[];
    for(int i=0;i<g_acts_len;i++) {
        if((method==g_acts[i].method)&&(strcmp(s_uri, g_acts[i].s_uri)==0)) return &g_acts[i];
    }
    return NULL;
}
#define ACT(m, u, ...)     { m, sizeof(u)-1, u, __VA_ARGS__ }
/*----------------------------------------------------------------------------*/
static void post_small(FCGX_Request *req) {
    int rc = 0;
    char buf[BUF_SIZE] = {0}; /* POST DATA */
    if((rc=req_body(req, buf, sizeof(buf)))>0) {
        buf[rc] = '\0';
        fprintf(stderr, "POST SIZE = %d, %s\n", rc, buf);
        make_response(req, HTTP_200, MIME_TEXT, "echo:%s", buf);
    } else {
        make_response(req, HTTP_200, MIME_TEXT, "error, no body");
    }
}
/*----------------------------------------------------------------------------*/
const struct act_t g_acts[] = {
    ACT(METHOD_POST, "/small", .on_resp=post_small),
};
const int g_acts_len = ARRAY_LEN(g_acts);

static void dispach(FCGX_Request *req) {
    const char *m = req_method(req);
    enum method_t method = http_method(m, strlen(m));
    const char *uri = req_uri(req);
    const struct act_t *act = find_action(method, uri);
    log_debug("uri=%s, method=%s, act=%p", uri, m, (void *)act);
    if(!act) {
        make_response(req, HTTP_403, MIME_TEXT, "no action");
        return;
    }
    act->on_resp(req);
}

int main(int argc, char *argv[]) {
    fprintf(stderr, "LISTEN=/tmp/fastcgi.socket ./mycgi\n");
    const char* addr = getenv("LISTEN");
    const char* env_val = getenv("TRACE");
    if (env_val) g_env.trace_level = atoi(env_val);
    int sock = -1;
    if ((FCGX_Init()!=0) || ((sock = FCGX_OpenSocket(addr ? addr : DEF_ADDR, 128))<0)) {
        perror("FCGX INIT");
        return 1;
    }
    FCGX_Request request;
    if (FCGX_InitRequest(&request, sock, 0)!=0) {
        fprintf(stderr, "FCGX_InitRequest failed\n");
        return 1;
    }
    for(;;) {
        int rc = FCGX_Accept_r(&request);
        if (rc!=0) {
            fprintf(stderr, "Accept failed: %d\n", rc);
            break;
        }
        dispach(&request);
        FCGX_Finish_r(&request);
    }
    return 0;
}
/*
# sudo apt install autoconf automake libtool
# git clone https://github.com/FastCGI-Archives/fcgi2.git
upstream fcgi_srvs {
        server 127.0.0.1:9999;
        server unix:/tmp/fastcgi.socket;
        keepalive 16;
}
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
        allow 127.0.0.1;
        deny all;
        fastcgi_keep_conn on;
        if ($request_method !~ ^(GET|HEAD)$) { return 405; }
        include /etc/nginx/fastcgi_params;
        fastcgi_param YOURENV Profile;
        fastcgi_pass fcgi_srvs;
    }
}
*/
