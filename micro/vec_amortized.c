// C equivalent of vec_amortized.hl.
// Build + consume in a single timed region, hand-rolled
// realloc-doubling buffer. Caveat: Go amortizes GC inside the
// region; C's free happens after t1 (matching the Go timed-region
// boundaries, which also exclude any explicit collection).
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
    long long n = 200000;
    long long t0 = now_ns();

    Vec v = {0, 0, 0};
    for (long long i = 0; i < n; i++) {
        vec_push(&v, i);
    }
    long long sum = 0;
    for (long long j = 0; j < n; j++) {
        sum += v.data[j];
    }

    long long elapsed = now_ns() - t0;
    printf("n=%lld\n", n);
    printf("sum=%lld\n", sum);
    printf("elapsed_ns=%lld\n", elapsed);
    free(v.data);
    return 0;
}
