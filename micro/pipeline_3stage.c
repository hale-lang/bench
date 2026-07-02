// C equivalent of pipeline_3stage.hl.
// Three components connected by a subject-keyed router table — the
// same shape as bus_dispatch.c, just with two hops. Each publish is
// an FNV-hashed lookup + strcmp verify + indirect call (no queue,
// no memcpy like Hale's bus pays). Event and Filtered are both
// single-int payloads, so one handler signature covers both — same
// data as the Go version's typed maps.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static long long now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000000000LL + (long long)ts.tv_nsec;
}

typedef void (*Handler)(void *ctx, long long value);

// Tiny string-keyed handler table (FNV-1a hash, linear probe,
// strcmp verify) — stands in for Go's map[string]func.
typedef struct {
    const char *subject;
    Handler fn;
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

static void router_add(Router *r, const char *subject, Handler fn, void *ctx) {
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
} Sink;

__attribute__((noinline)) static void on_filtered(void *ctx, long long value) {
    Sink *s = ctx;
    s->count++;
    s->sum += value;
}

typedef struct {
    long long passed;
    Router *router;
} Filter;

__attribute__((noinline)) static void on_event(void *ctx, long long value) {
    Filter *f = ctx;
    if (value % 2 == 0) {
        f->passed++;
        Route *rt = router_lookup(f->router, "filtered"); // per-event, like the Go version
        if (!rt) exit(1);
        rt->fn(rt->ctx, value);
    }
}

typedef struct {
    long long count;
    Router *router;
} Source;

static void source_run(Source *s) {
    Route *emit = router_lookup(s->router, "event"); // hoisted, like the Go version
    if (!emit) exit(1);
    for (long long i = 0; i < s->count; i++) {
        emit->fn(emit->ctx, i);
    }
}

int main(void) {
    long long n = 50000;
    Sink sink = {0, 0};
    Router filtered_router = {0};
    router_add(&filtered_router, "filtered", on_filtered, &sink);
    Filter filter = {0, &filtered_router};
    Router event_router = {0};
    router_add(&event_router, "event", on_event, &filter);
    Source source = {n, &event_router};

    long long t0 = now_ns();
    source_run(&source);
    long long elapsed = now_ns() - t0;

    printf("n=%lld\n", n);
    printf("filter_passed=%lld\n", filter.passed);
    printf("sink_count=%lld\n", sink.count);
    printf("sink_sum=%lld\n", sink.sum);
    printf("elapsed_ns=%lld\n", elapsed);
    return 0;
}
