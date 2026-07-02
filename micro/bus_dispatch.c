// C equivalent of bus_dispatch.hl.
// Subject-keyed handler dispatch — an FNV-hashed table lookup +
// strcmp verify + indirect call per publish, mirroring the Go
// version's map[string]func router (and Hale's bus router). NOT
// direct fn calls: those skip the subject match Hale pays for.
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
    long long n;
} Tick;

typedef void (*TickHandler)(void *ctx, Tick t);

// Tiny string-keyed handler table (FNV-1a hash, linear probe,
// strcmp verify) — stands in for Go's map[string]func.
typedef struct {
    const char *subject;
    TickHandler fn;
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

static void router_add(Router *r, const char *subject, TickHandler fn, void *ctx) {
    unsigned long long i = fnv1a(subject) & 3;
    while (r->slots[i].subject) i = (i + 1) & 3;
    r->slots[i] = (Route){subject, fn, ctx};
}

// noinline: the per-publish subject match stays a real call.
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
} Aggregator;

static void on_tick(void *ctx, Tick t) {
    Aggregator *a = ctx;
    a->count++;
    (void)t;
}

int main(void) {
    long long iters = 100000;
    Aggregator agg = {0};
    Router router = {0};
    router_add(&router, "bench.tick", on_tick, &agg);

    long long t0 = now_ns();
    for (long long i = 0; i < iters; i++) {
        Route *rt = router_lookup(&router, "bench.tick");
        if (!rt) exit(1);
        rt->fn(rt->ctx, (Tick){.n = i});
    }
    long long elapsed = now_ns() - t0;

    printf("iters=%lld\n", iters);
    printf("count=%lld\n", agg.count);
    printf("elapsed_ns=%lld\n", elapsed);
    return 0;
}
