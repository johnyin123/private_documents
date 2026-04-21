#include <fcgiapp.h>
#include <stdio.h>
struct env_t {
    int sock;
} env = {
    .sock  = -1,
};
/*-------------------------------*/
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#define ARRAY_LEN(a)  (sizeof(a)/sizeof((a)[0]))
#define MAX_CONNS     128
struct queue_t {
    void **elems; int cap;
    int head, tail, count;
    pthread_mutex_t mutex;
    pthread_cond_t not_empty;
    pthread_cond_t not_full;
    volatile int stop;
};
void queue_init(struct queue_t *q, void *elems, size_t size) {
    memset(q, 0, sizeof(*q));
    q->elems = elems;
    q->cap = size;
    pthread_mutex_init(&q->mutex, NULL);
    pthread_cond_init(&q->not_empty, NULL);
    pthread_cond_init(&q->not_full, NULL);
}
void queue_stop(struct queue_t *q) {
    q->stop=1;
    pthread_mutex_lock(&q->mutex);
    pthread_cond_broadcast(&q->not_empty);
    pthread_cond_broadcast(&q->not_full);
    pthread_mutex_unlock(&q->mutex);
}
void queue_destroy(struct queue_t *q) {
    pthread_mutex_destroy(&q->mutex);
    pthread_cond_destroy(&q->not_empty);
    pthread_cond_destroy(&q->not_full);
}
int queue_push(struct queue_t *q, void *elem) {
    pthread_mutex_lock(&q->mutex);
    while (q->count >= q->cap && !q->stop) {
        pthread_cond_wait(&q->not_full, &q->mutex);
    }
    if (q->stop) {
        pthread_mutex_unlock(&q->mutex);
        return EXIT_FAILURE;
    }
    q->elems[q->tail] = elem;
    q->tail = (q->tail + 1) % q->cap;
    q->count++;
    pthread_cond_signal(&q->not_empty);
    pthread_mutex_unlock(&q->mutex);
    return EXIT_SUCCESS;
}
void *queue_pop(struct queue_t *q) {
    pthread_mutex_lock(&q->mutex);
    while (q->count == 0 && !q->stop) {
        pthread_cond_wait(&q->not_empty, &q->mutex);
    }
    if (q->stop && q->count == 0) {
        pthread_mutex_unlock(&q->mutex);
        return NULL;
    }
    void *elem = q->elems[q->head];
    q->head = (q->head + 1) % q->cap;
    q->count--;
    pthread_cond_signal(&q->not_full);
    pthread_mutex_unlock(&q->mutex);
    return elem;
}
/*-------------------------------*/
void *acceptor_thread(void *arg) {
    struct queue_t *q = arg;
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
        FCGX_Request *req = queue_pop(q);
        if (req == NULL) break;
        char *uri = FCGX_GetParam("REQUEST_URI", req->envp);
        unsigned long tid = (unsigned long)pthread_self();
        FCGX_FPrintF(req->out,
            "Status: 200 OK\r\n"
            "Content-Type: text/plain\r\n"
            "\r\n"
            "[Thread %lu] Hello! URI: %s\n", tid, uri ? uri : "/");
        FCGX_Finish_r(req);
        free(req);
    }
    return NULL;
}
int main(int argc, char *argv[]) {
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
    printf("Running. Press Ctrl+C to stop.\n");
    getchar();
    queue_stop(&queue);
    pthread_join(acceptor, NULL);
    for (int i=0; i<4; i++) {
        pthread_join(workers[i], NULL);
    }
    queue_destroy(&queue);
    return 0;
}
