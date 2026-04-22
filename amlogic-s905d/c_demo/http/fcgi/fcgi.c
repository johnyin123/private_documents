#include "fcgi_utils.h"
#include <stdio.h>
#include <stdlib.h>
int main(int argc, char *argv[]) {
    UNUSED(argc);UNUSED(argv);
    const char* env_val = getenv("TRACE");
    if(env_val) g_env.trace_level = atoi(env_val);
    int sock = -1;
    if ((FCGX_Init()!=0) || ((sock = FCGX_OpenSocket("localhost:9999", 128)) < 0)) {
        perror("FCGX INIT");
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
        dump_request("fcgi", &request);
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
        allow 127.0.0.1;
        deny all;
        fastcgi_keep_conn on;
        if ($request_method !~ ^(GET|HEAD)$) { return 405; }
        include /etc/nginx/fastcgi_params;
        fastcgi_param YOURENV Profile;
        fastcgi_pass 127.0.0.1:9999;
    }
}
*/
