#include <fcgiapp.h>
#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <unistd.h>
#include <errno.h>
#define MAX_CONNS 128
struct queue_t {
    FCGX_Request *requests[MAX_CONNS];
    int head, tail, count;
    pthread_mutex_t mutex;
    pthread_cond_t not_empty;
    pthread_cond_t not_full;
};
struct env_t {
    struct queue_t queue;
    int sock;
    int stop;
} env = {
    .sock  = -1,
    .stop  = 0,
};
void queue_init(struct queue_t *q) {
    q->head = q->tail = q->count = 0;
    pthread_mutex_init(&q->mutex, NULL);
    pthread_cond_init(&q->not_empty, NULL);
    pthread_cond_init(&q->not_full, NULL);
}
void queue_push(struct queue_t *q, FCGX_Request *req) {
    pthread_mutex_lock(&q->mutex);
    while (q->count >= MAX_CONNS && !env.stop) {
        pthread_cond_wait(&q->not_full, &q->mutex);
    }
    if (env.stop) {
        pthread_mutex_unlock(&q->mutex);
        return;
    }
    q->requests[q->tail] = req;
    q->tail = (q->tail + 1) % MAX_CONNS;
    q->count++;
    pthread_cond_signal(&q->not_empty);
    pthread_mutex_unlock(&q->mutex);
}
FCGX_Request *queue_pop(struct queue_t *q) {
    pthread_mutex_lock(&q->mutex);
    while (q->count == 0 && !env.stop) {
        pthread_cond_wait(&q->not_empty, &q->mutex);
    }
    if (env.stop && q->count == 0) {
        pthread_mutex_unlock(&q->mutex);
        return NULL;
    }
    FCGX_Request *req = q->requests[q->head];
    q->head = (q->head + 1) % MAX_CONNS;
    q->count--;
    pthread_cond_signal(&q->not_full);
    pthread_mutex_unlock(&q->mutex);
    return req;
}
void *acceptor_thread(void *arg) {
    for (;;) {
        FCGX_Request *req = malloc(sizeof(FCGX_Request));
        if (FCGX_InitRequest(req, env.sock, 0) != 0) {
            free(req);
            continue;
        }
        int rc = FCGX_Accept_r(req);
        if (rc < 0) {
            fprintf(stderr, "Accept failed: %d\n", rc);
            free(req);
            if (env.stop) break;
            continue;
        }
        queue_push(&env.queue, req);
    }
    return NULL;
}
void *worker_thread(void *arg) {
    int tid = *(int *)arg;
    free(arg);
    for (;;) {
        FCGX_Request *req = queue_pop(&env.queue);
        if (req == NULL) break;
        char *uri = FCGX_GetParam("REQUEST_URI", req->envp);
        FCGX_FPrintF(req->out,
            "Status: 200 OK\r\n"
            "Content-Type: text/plain\r\n"
            "\r\n"
            "[Thread %d] Hello! URI: %s\n", tid, uri ? uri : "/");
        FCGX_Finish_r(req);
        free(req);
    }
    return NULL;
}
int main(int argc, char *argv[]) {
    if (FCGX_Init() != 0) {
        fprintf(stderr, "FCGX_Init failed\n");
        return 1;
    }
    env.sock = FCGX_OpenSocket("localhost:9999", 128);
    if (env.sock < 0) {
        perror("FCGX_OpenSocket");
        return 1;
    }
    queue_init(&env.queue);
    /* 1 acceptor + 4 worker */
    pthread_t acceptor;
    pthread_create(&acceptor, NULL, acceptor_thread, NULL);
    pthread_t workers[4];
    for (int i = 0; i < 4; i++) {
        int *tid = malloc(sizeof(int));
        *tid = i;
        pthread_create(&workers[i], NULL, worker_thread, tid);
    }
    printf("Running. Press Ctrl+C to stop.\n");
    getchar();
    env.stop = 1;
    pthread_cond_broadcast(&env.queue.not_empty);
    pthread_cond_broadcast(&env.queue.not_full);
    pthread_join(acceptor, NULL);
    for (int i = 0; i < 4; i++) {
        pthread_join(workers[i], NULL);
    }
    return 0;
}
