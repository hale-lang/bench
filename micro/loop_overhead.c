// C equivalent of loop_overhead.hl.
// XOR accumulation defeats DCE without overflow concerns; getpid()
// seeds iters/acc so clang can't constant-fold the loop. Caveat:
// clang may vectorize the XOR loop (fair — Hale lowers via LLVM
// too; Go does not auto-vectorize).
#include <stdio.h>
#include <time.h>
#include <unistd.h>

static long long now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000000000LL + (long long)ts.tv_nsec;
}

int main(void) {
    long long iters = 100000000 + getpid();
    long long t0 = now_ns();
    long long acc = getpid();
    for (long long i = 0; i < iters; i++) {
        acc = acc ^ i;
    }
    long long elapsed = now_ns() - t0;
    printf("iters=%lld\n", iters);
    printf("acc=%lld\n", acc);
    printf("elapsed_ns=%lld\n", elapsed);
    return 0;
}
