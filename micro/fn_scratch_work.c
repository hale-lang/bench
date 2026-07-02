// C equivalent of fn_scratch_work.hl.
// 100 fn calls × 1000-element local growable buffer each. Vec is a
// hand-rolled realloc-doubling buffer (libc has no growable array)
// — same growth policy as Go append / Hale @form(vec). Caveat: C
// frees the scratch buffer explicitly inside the call; Go leaves it
// to GC, Hale to arena reclaim.
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

__attribute__((noinline)) static long long do_work(long long n) {
    Vec v = {0, 0, 0};
    for (long long i = 0; i < n; i++) {
        vec_push(&v, i);
    }
    long long sum = 0;
    for (long long j = 0; j < n; j++) {
        sum += v.data[j];
    }
    free(v.data);
    return sum;
}

int main(void) {
    long long calls = 100;
    long long per_call = 1000;
    long long t0 = now_ns();
    long long total = 0;
    for (long long c = 0; c < calls; c++) {
        total += do_work(per_call);
    }
    long long elapsed = now_ns() - t0;
    printf("calls=%lld\n", calls);
    printf("per_call=%lld\n", per_call);
    printf("total=%lld\n", total);
    printf("elapsed_ns=%lld\n", elapsed);
    return 0;
}
