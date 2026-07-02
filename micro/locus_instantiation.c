// C equivalent of locus_instantiation.hl.
// Helper fn heap-allocates Empty, calls a method to return a field,
// XORs the result into a sink — matches the Hale/Go bench shape so
// nothing gets DCE'd. getpid() seeds the values. Caveats: C frees
// each instance immediately where Go defers to GC; and the asm
// barrier keeps clang from eliding the malloc/free pair the way
// Go's runtime can't.
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>

static long long now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000000000LL + (long long)ts.tv_nsec;
}

typedef struct {
    long long v;
} Empty;

__attribute__((noinline)) static long long empty_read(Empty *e) { return e->v; }

__attribute__((noinline)) static long long instantiate_one(long long seed) {
    Empty *e = malloc(sizeof *e);
    if (!e) exit(1);
    e->v = seed;
    asm volatile("" :: "r"(e) : "memory"); // keep the heap allocation real
    long long r = empty_read(e);
    free(e);
    return r;
}

int main(void) {
    long long iters = 100000;
    long long pid = getpid();
    long long t0 = now_ns();
    long long sink = 0;
    for (long long i = 0; i < iters; i++) {
        sink ^= instantiate_one(i + pid);
    }
    long long elapsed = now_ns() - t0;
    printf("iters=%lld\n", iters);
    printf("sink=%lld\n", sink);
    printf("elapsed_ns=%lld\n", elapsed);
    return 0;
}
