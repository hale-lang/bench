// C equivalent of fn_call.hl. Free-fn call overhead, minimal body.
// __attribute__((noinline)) forces a real call so it measures call
// overhead, not a folded-away loop. Caveat: unlike Go's
// //go:noinline, clang still does IPA purity analysis on noinline
// fns and would delete the dead pure calls — the asm barrier marks
// the result observed each iteration to keep every call real.
#include <stdio.h>
#include <time.h>

static long long now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000000000LL + (long long)ts.tv_nsec;
}

__attribute__((noinline)) static long long step(long long x) { return x * 2 + 1; }

int main(void) {
    long long iters = 10000000;
    long long t0 = now_ns();
    long long acc = 0;
    for (long long i = 0; i < iters; i++) {
        acc = step(i);
        asm volatile("" :: "r"(acc));
    }
    long long elapsed = now_ns() - t0;
    printf("iters=%lld\n", iters);
    printf("acc=%lld\n", acc);
    printf("elapsed_ns=%lld\n", elapsed);
    return 0;
}
