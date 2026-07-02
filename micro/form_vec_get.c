// C equivalent of form_vec_get.hl.
// Populate (outside timing) then time bounds-checked indexed reads.
// C has no implicit bounds check, so vec_get carries an explicit
// one — closest analog to Hale's `get(i) or raise` and Go's checked
// v[i]. Caveat: like Go's BCE, clang will hoist the provably
// in-range check; both sides get that break.
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

// Bounds-checked read — mirrors `get(i) or raise`.
static long long vec_get(const Vec *v, long long i) {
    if (i < 0 || (size_t)i >= v->len) exit(1);
    return v->data[i];
}

int main(void) {
    long long iters = 200000;
    Vec v = {0, 0, 0};
    for (long long i = 0; i < iters; i++) {
        vec_push(&v, i);
    }

    long long t0 = now_ns();
    long long acc = 0;
    for (long long j = 0; j < iters; j++) {
        acc ^= vec_get(&v, j);
    }
    long long elapsed = now_ns() - t0;

    printf("iters=%lld\n", iters);
    printf("acc=%lld\n", acc);
    printf("elapsed_ns=%lld\n", elapsed);
    free(v.data);
    return 0;
}
