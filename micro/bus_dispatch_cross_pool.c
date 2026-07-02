// C equivalent of bus_dispatch_cross_pool.hl.
// Two OS threads: main publishes, a worker subscribes. Cross-thread
// delivery via a bounded ring (cap 64, mirroring Hale's io pool
// queue depth) guarded by a pthread mutex + condvars — the C
// analogue of the Go version's buffered channel. pthreads are real
// OS threads, so no LockOSThread analogue is needed. Caveat: Go
// channels fast-path in userspace like this mutex does; both fall
// back to futex under contention.
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

static long long now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000000000LL + (long long)ts.tv_nsec;
}

typedef struct {
    long long n;
} Tick;

#define CHAN_CAP 64

// Bounded MPSC ring with mutex + condvars — Go `make(chan Tick, 64)`.
typedef struct {
    Tick buf[CHAN_CAP];
    int head, tail, count, closed;
    pthread_mutex_t mu;
    pthread_cond_t not_empty, not_full;
} Chan;

static void chan_init(Chan *c) {
    c->head = c->tail = c->count = c->closed = 0;
    pthread_mutex_init(&c->mu, NULL);
    pthread_cond_init(&c->not_empty, NULL);
    pthread_cond_init(&c->not_full, NULL);
}

static void chan_send(Chan *c, Tick t) {
    pthread_mutex_lock(&c->mu);
    while (c->count == CHAN_CAP) pthread_cond_wait(&c->not_full, &c->mu);
    c->buf[c->tail] = t;
    c->tail = (c->tail + 1) % CHAN_CAP;
    c->count++;
    pthread_cond_signal(&c->not_empty);
    pthread_mutex_unlock(&c->mu);
}

// Returns 1 with a tick, or 0 when the channel is closed and drained.
static int chan_recv(Chan *c, Tick *out) {
    pthread_mutex_lock(&c->mu);
    while (c->count == 0 && !c->closed) pthread_cond_wait(&c->not_empty, &c->mu);
    if (c->count == 0) {
        pthread_mutex_unlock(&c->mu);
        return 0;
    }
    *out = c->buf[c->head];
    c->head = (c->head + 1) % CHAN_CAP;
    c->count--;
    pthread_cond_signal(&c->not_full);
    pthread_mutex_unlock(&c->mu);
    return 1;
}

static void chan_close(Chan *c) {
    pthread_mutex_lock(&c->mu);
    c->closed = 1;
    pthread_cond_broadcast(&c->not_empty);
    pthread_mutex_unlock(&c->mu);
}

typedef struct {
    Chan *ch;
    long long count;
} Subscriber;

static void *subscriber_main(void *arg) {
    Subscriber *s = arg;
    Tick t;
    while (chan_recv(s->ch, &t)) {
        s->count++;
        (void)t;
    }
    return NULL;
}

int main(void) {
    long long iters = 100000;
    Chan ch;
    chan_init(&ch);
    Subscriber sub = {&ch, 0};
    pthread_t worker;
    if (pthread_create(&worker, NULL, subscriber_main, &sub) != 0) exit(1);

    long long t0 = now_ns();
    for (long long i = 0; i < iters; i++) {
        chan_send(&ch, (Tick){.n = i});
    }
    long long elapsed = now_ns() - t0;
    chan_close(&ch);
    pthread_join(worker, NULL);

    printf("iters=%lld\n", iters);
    printf("count=%lld\n", sub.count);
    printf("elapsed_ns=%lld\n", elapsed);
    return 0;
}
