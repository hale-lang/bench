// C equivalent of tree_fanout.hl.
// Parent struct loops K times, heap-constructs a Worker, invokes
// compute() on it (analogue of Hale's accept(w) → w.compute()),
// aggregates the result. K=20 matches Hale's accept() cliff so the
// ratio stays apples-to-apples. Caveat: C frees each Worker
// immediately; Go defers to GC.
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

static long long now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000000000LL + (long long)ts.tv_nsec;
}

typedef struct {
    long long id;
    long long batch_size;
} Worker;

__attribute__((noinline)) static long long worker_compute(Worker *w) {
    long long sum = 0;
    for (long long i = 0; i < w->batch_size; i++) {
        sum += i;
    }
    return sum;
}

typedef struct {
    long long num_workers;
    long long items_each;
    long long total;
} Coordinator;

__attribute__((noinline)) static void coordinator_accept(Coordinator *c, Worker *w) {
    c->total += worker_compute(w);
}

static void coordinator_run(Coordinator *c) {
    for (long long i = 0; i < c->num_workers; i++) {
        Worker *w = malloc(sizeof *w);
        if (!w) exit(1);
        w->id = i;
        w->batch_size = c->items_each;
        coordinator_accept(c, w);
        free(w);
    }
}

int main(void) {
    long long k = 20;
    long long m = 2000;
    long long t0 = now_ns();
    Coordinator c = {.num_workers = k, .items_each = m, .total = 0};
    coordinator_run(&c);
    long long elapsed = now_ns() - t0;
    printf("k=%lld\n", k);
    printf("m=%lld\n", m);
    printf("total_ops=%lld\n", k * m);
    printf("total=%lld\n", c.total);
    printf("elapsed_ns=%lld\n", elapsed);
    return 0;
}
