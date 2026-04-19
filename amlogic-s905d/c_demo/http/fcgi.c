#include <fcgiapp.h>
#include <stdio.h>
#include <stdlib.h>
int main(void) {
    int sock;
    FCGX_Request request;
    // init library
    if (FCGX_Init() != 0) {
        fprintf(stderr, "FCGX_Init failed\n");
        return 1;
    }
    // open TCP socket on 127.0.0.1:9999
    sock = FCGX_OpenSocket("127.0.0.1:9999", 128);
    if (sock < 0) {
        perror("FCGX_OpenSocket");
        return 1;
    }
    // init request
    if (FCGX_InitRequest(&request, sock, 0) != 0) {
        fprintf(stderr, "FCGX_InitRequest failed\n");
        return 1;
    }
    // main loop
    while (FCGX_Accept_r(&request) == 0) {
        FCGX_FPrintF(request.out,
                     "Content-Type: text/plain\r\n\r\n"
                     "Hello, FastCGI on 127.0.0.1:9999\n");
        FCGX_Finish_r(&request);
    }
    return 0;
}
