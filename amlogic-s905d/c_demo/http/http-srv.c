#include "http-srv.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/param.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>

#define PORT 8080
#define BACKLOG_SIZE 5
#define RESPONSE_BODY_SIZE 4096
#define OUTPUT_BUFFER_SIZE (4096 + 512)

char request_buffer[MAX_REQUEST_LEN] = { 0 };
char response_body[RESPONSE_BODY_SIZE] = { 0 };
char output_buffer[OUTPUT_BUFFER_SIZE] = { 0 };

int main(const int argc, char const* argv[]) {
    int srv_sock, cli_sock;
    struct sockaddr_in address = { .sin_family = AF_INET, .sin_addr.s_addr = inet_addr("127.0.0.1")/*INADDR_ANY*/, .sin_port = htons(PORT) };
    int addrlen = sizeof(address);
    if ((srv_sock = socket(AF_INET, SOCK_STREAM, 0)) == -1) {
        perror("In socket");
        exit(EXIT_FAILURE);
    }
    //int opt = 1;
    //if(setsockopt(srv_sock, SOL_SOCKET, SO_REUSEADDR, (char *)&opt, sizeof(opt)) < 0)
    //{
    //    perror("setsockopt");
    //    exit(EXIT_FAILURE);
    //}
    if (bind(srv_sock, (struct sockaddr*) &address, sizeof(address)) < 0) {
        perror("In bind");
        exit(EXIT_FAILURE);
    }
    if (listen(srv_sock, BACKLOG_SIZE) < 0) {
        perror("In listen");
        exit(EXIT_FAILURE);
    }
    while (1) {
        debugln("\n++++++++++ Waiting for new connection ++++++++++++\n\n");
        if ((cli_sock = accept(srv_sock, (struct sockaddr*)&address, (socklen_t*)&addrlen)) < 0) {
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
        const enum t_http_method method = getHttpMethod(request_buffer);
        const char* path = getHttpUri(request_buffer);
        const size_t pathLen = (size_t)strchr(path, ' ') - (size_t)path;
        struct t_response response = { .body = response_body, .time = time(0), };
        if (method == GET && (MATCHES(path, pathLen, "/ready") || MATCHES(path, pathLen, "/healthz"))) {
            strcpy(response_body, "{\"success\":\"true\"}");
            response.status = 200;
            response.mime = JSON;
            response.bodyContentLen = strnlen(response_body, RESPONSE_BODY_SIZE);
        } else {
            strcpy(response_body, "Forbidden");
            response.status = 403;
            response.mime = PLAIN_TEXT;
            response.bodyContentLen = strnlen(response_body, RESPONSE_BODY_SIZE);
        }
        createResponse(response, output_buffer, sizeof(output_buffer));
        debugln("Response: \n\n%s\n", output_buffer);
        write(cli_sock, output_buffer, strnlen(output_buffer, OUTPUT_BUFFER_SIZE));
        debugln("------------------Response sent-------------------\n");
        close(cli_sock);
    }
}
