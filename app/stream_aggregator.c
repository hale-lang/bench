// C equivalent of stream_aggregator.hl.
// Pub/sub aggregator: publisher fires N typed samples, an
// aggregator subscribes via subject-keyed dispatch (same
// FNV-hashed table + indirect call shape as bus_dispatch.c) and
// maintains running sum/min/max. The lookup is hoisted before the
// loop, matching the Go version.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static long long now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000000000LL + (long long)ts.tv_nsec;
}

typedef struct {
    long long value;
} Sample;

typedef void (*SampleHandler)(void *ctx, Sample s);

// Tiny string-keyed handler table (FNV-1a hash, linear probe,
// strcmp verify) — stands in for Go's map[string]func.
typedef struct {
    const char *subject;
    SampleHandler fn;
    void *ctx;
} Route;

typedef struct {
    Route slots[4];
} Router;

static unsigned long long fnv1a(const char *s) {
    unsigned long long h = 1469598103934665603ULL;
    for (; *s; s++) {
        h ^= (unsigned char)*s;
        h *= 1099511628211ULL;
    }
    return h;
}

static void router_add(Router *r, const char *subject, SampleHandler fn, void *ctx) {
    unsigned long long i = fnv1a(subject) & 3;
    while (r->slots[i].subject) i = (i + 1) & 3;
    r->slots[i] = (Route){subject, fn, ctx};
}

__attribute__((noinline)) static Route *router_lookup(Router *r, const char *subject) {
    unsigned long long i = fnv1a(subject) & 3;
    while (r->slots[i].subject) {
        if (strcmp(r->slots[i].subject, subject) == 0) return &r->slots[i];
        i = (i + 1) & 3;
    }
    return NULL;
}

typedef struct {
    long long count;
    long long sum;
    long long min_v;
    long long max_v;
} Aggregator;

static void on_sample(void *ctx, Sample s) {
    Aggregator *a = ctx;
    a->count++;
    a->sum += s.value;
    if (s.value < a->min_v) a->min_v = s.value;
    if (s.value > a->max_v) a->max_v = s.value;
}

int main(void) {
    long long iters = 200000;
    Aggregator agg = {0, 0, 999999999, 0};
    Router router = {0};
    router_add(&router, "bench.sample", on_sample, &agg);

    long long t0 = now_ns();
    Route *handler = router_lookup(&router, "bench.sample");
    if (!handler) exit(1);
    for (long long i = 0; i < iters; i++) {
        long long v = (i * 31 + 7) % 1000;
        handler->fn(handler->ctx, (Sample){.value = v});
    }
    long long elapsed = now_ns() - t0;

    printf("iters=%lld\n", iters);
    printf("count=%lld\n", agg.count);
    printf("sum=%lld\n", agg.sum);
    printf("elapsed_ns=%lld\n", elapsed);
    return 0;
}
