#include "fcgi_utils.h"
#include <stdio.h>
#include <stdlib.h>
#define MAX_CONNS  128

DEFINE_QUEUE_TYPE(FCGX_Request, req_queue, MAX_CONNS)
struct thread_arg_t {
    int sock;
    req_queue_t queue;
};
void *acceptor_thread(void *arg) {
    struct thread_arg_t *t_args = arg;
    for (;;) {
        if (req_queue_is_stop(&t_args->queue)) break;
        FCGX_Request *req = req_queue_reserve(&t_args->queue);
        if (!req) break;
        if ((FCGX_InitRequest(req, t_args->sock, 0) != 0) || (FCGX_Accept_r(req) < 0))
            continue;
        req_queue_commit(&t_args->queue);
    }
    log_error("accept thread exit");
    return NULL;
}
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
    make_response(req, 200, MIME_TEXT, "[Thread %lu]%s %s FastCGI\" }", tid, host ? host : "(null)", method ? method : "(null)", uri ? uri : "(null)");
    dump_request("fcgi", req);
    FCGX_Finish_r(req);
}
void *worker_thread(void *arg) {
    struct thread_arg_t *t_args = arg;
    for (;;) {
        if(req_queue_is_stop(&t_args->queue)) break;
        FCGX_Request *req=req_queue_peek(&t_args->queue);
        if(!req) continue;
        deal(req);
        req_queue_release(&t_args->queue);
    }
    log_error("worker thread exit");
    return NULL;
}
int main(int argc, char *argv[]) {
    const char* env_val = getenv("TRACE");
    if(env_val) g_env.trace_level = atoi(env_val);
    struct thread_arg_t thread_arg = { .sock = -1, };
    if ((FCGX_Init()!=0) || ((thread_arg.sock = FCGX_OpenSocket("localhost:9999", 128)) < 0)) {
        perror("FCGX INIT");
        return 1;
    }
    req_queue_init(&thread_arg.queue);
    /* 1 acceptor + 4 worker */
    pthread_t acceptor, workers[4];
    pthread_create(&acceptor, NULL, acceptor_thread, &thread_arg);
    for (int i=0; i<4; i++) {
        pthread_create(&workers[i], NULL, worker_thread, &thread_arg);
    }
    fprintf(stderr, "Running. Press Ctrl+C to stop.\n");
    getchar();
    req_queue_stop(&thread_arg.queue);
    pthread_join(acceptor, NULL);
    for (int i=0; i<4; i++) {
        pthread_join(workers[i], NULL);
    }
    req_queue_destroy(&thread_arg.queue);
    return 0;
}
