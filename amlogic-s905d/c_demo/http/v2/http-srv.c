#include "http-srv.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define UNUSED(arg) ((void)arg)
#define MIN(a, b) (((a) < (b)) ? (a) : (b))
#if defined(__WIN32__)
    #include <winsock2.h>
    #include <ws2tcpip.h>
    #define close_socket closesocket
#else
    #define close_socket close
    #include <sys/socket.h>
    #include <arpa/inet.h>
    #include <unistd.h>
    #include <netinet/tcp.h>
    #include <fcntl.h>
#endif

#define HTTP_PORT 8080
#define MAX_REQ_SIZE  1024
#define MAX_BODY_SIZE 4096
/******************/
static void do_test(const struct request_t* req, struct response_t *res);
static void do_post(const struct request_t* req, struct response_t *res);

typedef void (*route_func_t)(const struct request_t* req, struct response_t *res);
struct router_t {
    const char method[8];
    const char path[128];
    route_func_t func;
} router[] = {
    {.method = "GET",  .path = "/test", .func=do_test},
    {.method = "POST", .path = "/test", .func=do_post},
    {"", "", NULL}
};
static route_func_t find_route(struct request_t *req) {
    if (!req) return NULL;
    for(const struct router_t *r = router; r->func != NULL; r++) {
        if ((strcmp(req->method, r->method) == 0) && (strcmp(req->url, r->path) == 0)) {
            debugln("Route: %s, %s return %p", r->method, r->path, r->func);
            return r->func;
        }
    }
    debugln("Route: %s, %s return NULL", req->method, req->url);
    return NULL;
}
static void do_test(const struct request_t* req, struct response_t *res) {
    res->status = 200;
    res->mime = JSON;
    dump_request(req);
    res->body_len = (size_t)snprintf(res->body, MAX_BODY_SIZE, "{\"success\":true}");
}
static void do_post(const struct request_t* req, struct response_t *res) {
    res->status = 200;
    res->mime = JSON;
    dump_request(req);
    res->body_len = (size_t)snprintf(res->body, MAX_BODY_SIZE, "{\"success\":%zu}", (size_t)1000);
}
int create_tcp_server(const char *addr, int port, int backlog) {
    int srv_sock;
    struct sockaddr_in sa = { .sin_family = AF_INET, .sin_addr.s_addr = inet_addr(addr), .sin_port = htons(port) };
    if ((srv_sock = socket(AF_INET, SOCK_STREAM, 0)) == -1) return -1;
    setsockopt(srv_sock, SOL_SOCKET, SO_REUSEADDR, (void *)&(int){1}, sizeof(int));
    if (bind(srv_sock,(struct sockaddr*)&sa,sizeof(sa)) == -1 || listen(srv_sock, backlog) == -1) {
        close_socket(srv_sock);
#if defined(__WIN32__)
        WSACleanup();
#endif
        return -1;
    }
    return srv_sock;
}
/* echo "my inputdate here" | curl -v --request POST --data @- http://127.0.0.1:8080 */
int main(const int argc, char const* argv[]) {
#if defined(__WIN32__)
    WSADATA wsaData;
    int iResult = WSAStartup(MAKEWORD(2 ,2), &wsaData);
    if (iResult != 0) {
        printf("error at WSASturtup\n");
        return 0;
    }
#endif
    char res_body[MAX_BODY_SIZE];
    struct sockaddr_in addr;
    int addrlen = sizeof(addr);
    int srv_sock, cli_sock, read_len;
    debugln("Listen port %d", HTTP_PORT);
    if ((srv_sock = create_tcp_server("127.0.0.1", HTTP_PORT, 10)) == -1) {
        perror("Create socket");
        exit(EXIT_FAILURE);
    }
    while (1) {
        debugln("+++++ Waiting  conn +++++\n");
        if ((cli_sock = accept(srv_sock, (struct sockaddr*)&addr, (socklen_t*)&addrlen)) < 0) {
            perror("In accept");
            exit(EXIT_FAILURE);
        }
        struct request_t req;
        struct response_t res = { .body = res_body, .time = time(0), };
        int rc = parse(cli_sock, &req, &read_len);
        if ((rc == 0) && (read_len > 0)) {
            res.status = 403;
            res.mime = PLAIN_TEXT;
            res.body_len = (size_t)snprintf(res_body, MAX_BODY_SIZE, "Forbidden");
            route_func_t func = find_route(&req);
            if (func) {
                func(&req, &res);
            } else { /*no found*/
                dump_request(&req);
                res.status = 404;
                res.mime = PLAIN_TEXT;
                res.body_len = (size_t)snprintf(res_body, MAX_BODY_SIZE, "NOFOUND");
            }
            if(send_response(cli_sock, &req, &res) == 0)
                debugln("----- Response sent -----");
            else
                debugln("XXXXX Response sent ERR-----");
        } else {
            debugln("parse http request error: %s", get_state_info(-rc));
        }
        if (read_len < 0) perror("Read error");
        debugln("----- Client closed rc=%d, reads=%d-----", rc, read_len);
        shutdown(cli_sock, SHUT_WR);
        close_socket(cli_sock);
    }
#if defined(__WIN32__)
    WSACleanup();
#endif
}
