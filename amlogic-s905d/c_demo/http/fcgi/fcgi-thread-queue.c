#include "fcgi_utils.h"
#include <stdio.h>
#include <stdlib.h>
#define N_WORKERS  5
#define MAX_CONNS  128
DEFINE_QUEUE_TYPE(FCGX_Request, req_queue, MAX_CONNS)
struct thread_arg_t {
    int sock;
    req_queue_t free_q, used_q;
    FCGX_Request reqs[MAX_CONNS];
};
void *acceptor_thread(void *arg) {
    struct thread_arg_t *t_args = arg;
    FCGX_Request *req;
    for (;;) {
        //stop
        while (!(req = req_queue_pop(&t_args->free_q))) {
            sched_yield();
        }
        if ((FCGX_InitRequest(req, t_args->sock, 0) != 0) || (FCGX_Accept_r(req) < 0)) {
            while (!req_queue_push(&t_args->free_q, req)) {
                sched_yield();
            }
            continue;
        }
        while (!req_queue_push(&t_args->used_q, req)) {
            sched_yield();
        }
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
}
void *worker_thread(void *arg) {
    struct thread_arg_t *t_args = arg;
    FCGX_Request *req;
    for (;;) {
        while (!(req = req_queue_pop(&t_args->used_q))) {
            sched_yield();
        }
        deal(req);
        FCGX_Finish_r(req);
        while (!req_queue_push(&t_args->free_q, req)) {
            sched_yield();
        }
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
    req_queue_init(&thread_arg.free_q);
    req_queue_init(&thread_arg.used_q);
    for (int i=0; i<MAX_CONNS; i++) {
        while (!req_queue_push(&thread_arg.free_q, &thread_arg.reqs[i])) { }
    }
    /* 1 acceptor + N_WORKERS worker */
    pthread_t acceptor, workers[N_WORKERS];
    pthread_create(&acceptor, NULL, acceptor_thread, &thread_arg);
    for (int i=0; i<N_WORKERS; i++) {
        pthread_create(&workers[i], NULL, worker_thread, &thread_arg);
    }
    fprintf(stderr, "Running. Press Ctrl+C to stop.\n");
    getchar();
    pthread_join(acceptor, NULL);
    for (int i=0; i<N_WORKERS; i++) {
        pthread_join(workers[i], NULL);
    }
    return 0;
}
