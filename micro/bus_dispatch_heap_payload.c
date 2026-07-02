// C equivalent of bus_dispatch_heap_payload.hl.
// Same subject-keyed dispatch as bus_dispatch.c, but the payload
// carries a String field: each publish strdup()s the label on the
// receive side and frees it after the handler returns — standing in
// for Hale's str_clone-into-subscriber-arena wire-codec path.
// Caveat: malloc/free per message vs Hale's arena bump-alloc.
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
    const char *label;
} Beat;

typedef void (*BeatHandler)(void *ctx, Beat b);

// Tiny string-keyed handler table (FNV-1a hash, linear probe,
// strcmp verify) — stands in for Hale's bus subject match.
typedef struct {
    const char *subject;
    BeatHandler fn;
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

static void router_add(Router *r, const char *subject, BeatHandler fn, void *ctx) {
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
} Counter;

static void on_beat(void *ctx, Beat b) {
    Counter *c = ctx;
    c->count++;
    (void)b;
}

// Subject match + receive-side clone of the heap payload + indirect
// call + reclaim — one bus delivery.
__attribute__((noinline)) static void publish(Router *r, const char *subject, Beat b) {
    Route *rt = router_lookup(r, subject);
    if (!rt) exit(1);
    char *cloned = strdup(b.label);
    if (!cloned) exit(1);
    rt->fn(rt->ctx, (Beat){.n = b.n, .label = cloned});
    free(cloned);
}

int main(void) {
    // Half the iter count of bus_dispatch.c, matching the .hl's
    // rationale for its heap-payload variant.
    long long iters = 50000;
    Counter c = {0};
    Router router = {0};
    router_add(&router, "bench.beat.heap", on_beat, &c);

    long long t0 = now_ns();
    for (long long i = 0; i < iters; i++) {
        publish(&router, "bench.beat.heap", (Beat){.n = i, .label = "tick"});
    }
    long long elapsed = now_ns() - t0;

    printf("iters=%lld\n", iters);
    printf("count=%lld\n", c.count);
    printf("elapsed_ns=%lld\n", elapsed);
    return 0;
}
