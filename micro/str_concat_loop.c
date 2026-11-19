// C equivalent of str_concat_loop.hl — a buffer that doubles when full.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static long long now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000000000LL + ts.tv_nsec;
}

int main(void) {
    int iters = 1000000;
    long long t0 = now_ns();
    size_t len = 0, cap = 16;
    char *s = malloc(cap);
    for (int i = 0; i < iters; i++) {
        if (len + 2 > cap) { cap *= 2; s = realloc(s, cap); }
        memcpy(s + len, "ab", 2);
        len += 2;
    }
    long long elapsed = now_ns() - t0;
    printf("iters=%d\nlen=%zu\nelapsed_ns=%lld\n", iters, len, elapsed);
    free(s);
    return 0;
}
