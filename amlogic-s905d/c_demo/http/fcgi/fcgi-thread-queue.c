#include "fcgi_utils.h"
#include <stdio.h>
#include <stdlib.h>
#define MAX_CONNS  128

struct env_t {
    int sock;
} env = {
    .sock  = -1,
};
void *acceptor_thread(void *arg) {
    struct queue_t *q = arg;
    for (;;) {
        if (q->stop) break;
        FCGX_Request *req = malloc(sizeof(FCGX_Request));
        if (FCGX_InitRequest(req, env.sock, 0) != 0) {
            free(req);
            continue;
        }
        int rc = FCGX_Accept_r(req);
        if (rc < 0) {
            fprintf(stderr, "Accept failed: %d\n", rc);
            free(req);
            if (q->stop) break;
            continue;
        }
        queue_push(q, req);
    }
    return NULL;
}
void *worker_thread(void *arg) {
    struct queue_t *q = arg;
    for (;;) {
        if (q->stop) break;
        FCGX_Request *req = queue_pop(q);
        if (req == NULL) break;
        const char *host = req_get_header(req, "FN_HANDLER");
        const char *method = req_method(req);
        const char *uri = req_uri(req);
        unsigned long tid = (unsigned long)pthread_self();
        int rc = 0;
        char buf[BUF_SIZE] = {0}; /* POST DATA */
        if((rc=req_body(req, buf, sizeof(buf)))>0) {
            buf[rc] = '\0';
            fprintf(stderr, "POST SIZE = %d, %s\n", rc, buf);
        }
        make_response(req, 200, MIME_TEXT, "[Thread %lu]%s %s FastCGI\" }", tid, host ? host : "(null)", method ? method : "(null)", uri ? uri : "(null)");
        dump_request("fcgi", req);
        FCGX_Finish_r(req);
        free(req);
    }
    return NULL;
}
int main(int argc, char *argv[]) {
    const char* env_val = getenv("TRACE");
    if(env_val) g_env.trace_level = atoi(env_val);
    FCGX_Request *reqs[MAX_CONNS];
    struct queue_t queue;
    if (FCGX_Init() != 0) {
        fprintf(stderr, "FCGX_Init failed\n");
        return 1;
    }
    env.sock = FCGX_OpenSocket("localhost:9999", 128);
    if (env.sock < 0) {
        perror("FCGX_OpenSocket");
        return 1;
    }
    queue_init(&queue, reqs, ARRAY_LEN(reqs));
    /* 1 acceptor + 4 worker */
    pthread_t acceptor, workers[4];
    pthread_create(&acceptor, NULL, acceptor_thread, &queue);
    for (int i=0; i<4; i++) {
        pthread_create(&workers[i], NULL, worker_thread, &queue);
    }
    fprintf(stderr, "Running. Press Ctrl+C to stop.\n");
    getchar();
    queue_stop(&queue);
    pthread_join(acceptor, NULL);
    for (int i=0; i<4; i++) {
        pthread_join(workers[i], NULL);
    }
    queue_destroy(&queue);
    return 0;
}
