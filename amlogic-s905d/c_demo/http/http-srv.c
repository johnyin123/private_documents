#include "http-srv.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/param.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>

#define HTTP_PORT 8080
#define BACKLOG_SIZE 5
#define MAX_BODY_SIZE 4096
#define BUFFER_SIZE (4096 + 512) /*body + response header*/

char request_buffer[MAX_REQUEST_LEN] = { 0 };
char response_body[MAX_BODY_SIZE] = { 0 };
char output_buffer[BUFFER_SIZE] = { 0 };

/******************/
static void do_test(const char *req, struct response_t *res);

typedef void (*route_func_t)(const char *req, struct response_t *res);
struct router_t {
    enum method_t method;
    const char* uri;
    route_func_t func;
} router[] = {
    {.method = GET, .uri = "/test", .func=do_test},
    {UNKNOWN, NULL, NULL}
};
static route_func_t chk_router(enum method_t method, const char *path, int len) {
    debugln("Route: %d, %.*s\n", method, len, path);
    for(struct router_t *r = router; r->method != UNKNOWN; r++) {
        if (r->method == method && len == strlen(r->uri) && strncmp(path, r->uri, len) == 0) {
            debugln("Route: return %p\n", r->func);
            return r->func;
        }
    }
    debugln("Route: return NULL\n");
    return NULL;
}
static void do_test(const char *req, struct response_t *res) {
    debugln("----- do_test request: \n%s\n", request_buffer);
    strcpy(res->body, "{\"success\":\"true\"}");
    res->status = 200;
    res->mime = JSON;
    res->bodyContentLen = strnlen(res->body, MAX_BODY_SIZE);
    return;
}
int main(const int argc, char const* argv[]) {
    struct sockaddr_in addr = { .sin_family = AF_INET, .sin_addr.s_addr = inet_addr("127.0.0.1")/*INADDR_ANY*/, .sin_port = htons(HTTP_PORT) };
    int addrlen = sizeof(addr);
    int srv_sock, cli_sock;
    debugln("Listen port %d\n", HTTP_PORT);
    if ((srv_sock = socket(AF_INET, SOCK_STREAM, 0)) == -1) {
        perror("In socket");
        exit(EXIT_FAILURE);
    }
    if (bind(srv_sock, (struct sockaddr*) &addr, sizeof(addr)) < 0) {
        perror("In bind");
        exit(EXIT_FAILURE);
    }
    if (listen(srv_sock, BACKLOG_SIZE) < 0) {
        perror("In listen");
        exit(EXIT_FAILURE);
    }
    while (1) {
        debugln("\n+++++ Waiting for new connection +++++\n\n");
        if ((cli_sock = accept(srv_sock, (struct sockaddr*)&addr, (socklen_t*)&addrlen)) < 0) {
            perror("In accept");
            exit(EXIT_FAILURE);
        }
        const ssize_t bytes_read = read(cli_sock, request_buffer, sizeof(request_buffer));
        if (bytes_read < 0) {
            perror("Read error");
            close(cli_sock);
            continue;
        }
        request_buffer[MIN((size_t)bytes_read, sizeof(request_buffer) - 1)] = '\0';
        debugln("Incoming request: \n\n%s\n", request_buffer);
        const enum method_t method = getHttpMethod(request_buffer);
        const char* path = getHttpUri(request_buffer);
        const size_t pathLen = (size_t)strchr(path, ' ') - (size_t)path;
        struct response_t response = { .body = response_body, .time = time(0), };
        route_func_t func = chk_router(method, path, pathLen);
        if (func != NULL) {
            func(request_buffer, &response);
        } else {
            /*no found*/
            strcpy(response_body, "Forbidden");
            response.status = 403;
            response.mime = PLAIN_TEXT;
            response.bodyContentLen = strnlen(response_body, MAX_BODY_SIZE);
        }
        createResponse(response, output_buffer, sizeof(output_buffer));
        debugln("Response: \n\n%s\n", output_buffer);
        write(cli_sock, output_buffer, strnlen(output_buffer, BUFFER_SIZE));
        debugln("------------------Response sent-------------------\n");
        close(cli_sock);
    }
}
