// C equivalent of fn_modular.hl — helper calls helper.
// __attribute__((noinline)) on both so it measures real call-chain
// overhead, not a folded loop. Caveat: clang's IPA purity analysis
// would delete the dead pure calls even when noinline — the asm
// barrier keeps each iteration's result observed.
#include <stdio.h>
#include <time.h>

static long long now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000000000LL + (long long)ts.tv_nsec;
}

__attribute__((noinline)) static long long inner(long long x) { return x + 1; }

__attribute__((noinline)) static long long outer(long long x) { return inner(x) * 3; }

int main(void) {
    long long iters = 10000000;
    long long t0 = now_ns();
    long long acc = 0;
    for (long long i = 0; i < iters; i++) {
        acc = outer(i);
        asm volatile("" :: "r"(acc));
    }
    long long elapsed = now_ns() - t0;
    printf("iters=%lld\n", iters);
    printf("acc=%lld\n", acc);
    printf("elapsed_ns=%lld\n", elapsed);
    return 0;
}
