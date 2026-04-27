#include "fcgi_utils.h"
#include <stdio.h>
#include <stdlib.h>
#define N_WORKERS  4
#define MAX_CONNS  128
#define DEF_ADDR   "localhost:9999"
struct thread_arg_t {
    int sock;
};
static void deal(FCGX_Request *req) {
    const char *host = req_get_header(req, "FN_HANDLER");
    const char *method = req_method(req);
    const char *uri = req_uri(req);
    unsigned long tid = (unsigned long)pthread_self();
    int rc = 0;
    char buf[BUF_SIZE] = {0}; /* POST DATA */
    if((rc=req_body(req, buf, ARRAY_LEN(buf)))>0) {
        buf[rc] = '\0';
        fprintf(stderr, "POST SIZE = %d, %s\n", rc, buf);
    }
    make_response(req, HTTP_200, MIME_TEXT, "[Thread %lu]%s %s FastCGI\" }", tid, host ? host : "(null)", method ? method : "(null)", uri ? uri : "(null)");
    //dump_request("fcgi", req);
}
void *worker_thread(void *arg) {
    struct thread_arg_t *t_args = arg;
    for (;;) {
        FCGX_Request req;
        if ((FCGX_InitRequest(&req, t_args->sock, 0)!=0) || (FCGX_Accept_r(&req)!=0)) {
            FCGX_Finish_r(&req);
            continue;
        }
        deal(&req);
        FCGX_Finish_r(&req);
    }
    log_info("worker exit");
    return NULL;
}
int main(int argc, char *argv[]) {
    fprintf(stderr, "LISTEN=/tmp/fastcgi.socket ./mycgi");
    const char* addr = getenv("LISTEN");
    const char* env_val = getenv("TRACE");
    if(env_val) g_env.trace_level = atoi(env_val);
    struct thread_arg_t thread_arg = { .sock = -1, };
    if ((FCGX_Init()!=0) || ((thread_arg.sock = FCGX_OpenSocket(addr ? addr : DEF_ADDR, 128)) < 0)) {
        perror("FCGX INIT");
        return 1;
    }
    /* N worker */
    pthread_t workers[N_WORKERS];
    for (int i=0; i<N_WORKERS; i++) {
        pthread_create(&workers[i], NULL, worker_thread, &thread_arg);
    }
    fprintf(stderr, "Running. Press Ctrl+C to stop.\n");
    getchar();
    for (int i=0; i<N_WORKERS; i++) {
        pthread_join(workers[i], NULL);
    }
    return 0;
}
