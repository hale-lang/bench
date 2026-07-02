// C equivalent of coord_with_churn.hl.
// Parent struct with a method that constructs + discards K heap
// Workers, invoking on_accept per child — closest analog to Hale's
// chunked-class parent with accept(w: Worker). K=2000 to keep the
// Go/Hale ratio (the Hale bench's accept() ceiling caps at ~25
// under v1 codegen). Caveats: C frees each Worker immediately where
// Go defers to GC; and the asm barrier in on_accept keeps the empty
// call + allocation real under clang's IPA (Go's //go:noinline
// alone suffices there).
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
} Worker;

typedef struct {
    long long batch;
} Coord;

__attribute__((noinline)) static void coord_on_accept(Coord *c, Worker *w) {
    (void)c;
    asm volatile("" :: "r"(w) : "memory");
}

__attribute__((noinline)) static void coord_run(Coord *c) {
    for (long long i = 0; i < c->batch; i++) {
        Worker *w = malloc(sizeof *w);
        if (!w) exit(1);
        w->n = i;
        coord_on_accept(c, w);
        free(w);
    }
}

int main(void) {
    long long k = 2000;
    long long t0 = now_ns();
    Coord c = {.batch = k};
    coord_run(&c);
    long long elapsed = now_ns() - t0;
    printf("k=%lld\n", k);
    printf("elapsed_ns=%lld\n", elapsed);
    return 0;
}
