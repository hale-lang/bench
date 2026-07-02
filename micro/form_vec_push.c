// C equivalent of form_vec_push.hl.
// Push to a hand-rolled realloc-doubling buffer from cap=0 (libc
// has no growable array) — same doubling growth policy as Hale's
// @form(vec) and Go append. Caveat: realloc may grow in place where
// Go/Hale always move on growth; amortized cost is the comparison.
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

static long long now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000000000LL + (long long)ts.tv_nsec;
}

// Growable int64 buffer: doubling realloc from a small seed cap.
typedef struct {
    long long *data;
    size_t len, cap;
} Vec;

static void vec_push(Vec *v, long long x) {
    if (v->len == v->cap) {
        v->cap = v->cap ? v->cap * 2 : 8;
        v->data = realloc(v->data, v->cap * sizeof *v->data);
        if (!v->data) exit(1);
    }
    v->data[v->len++] = x;
}

int main(void) {
    long long iters = 500000;
    Vec v = {0, 0, 0};
    long long t0 = now_ns();
    for (long long i = 0; i < iters; i++) {
        vec_push(&v, i);
    }
    long long elapsed = now_ns() - t0;
    printf("iters=%lld\n", iters);
    printf("len=%lld\n", (long long)v.len);
    printf("elapsed_ns=%lld\n", elapsed);
    free(v.data);
    return 0;
}
