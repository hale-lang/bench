// C equivalent of str_csv_sum.hl — a hand-written scan with strtol.
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

static long long now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000000000LL + ts.tv_nsec;
}

int main(void) {
    char *csv = malloc(1 << 16);
    size_t off = 0;
    for (int i = 0; i < 1000; i++) off += sprintf(csv + off, "%d,17,4,250,9,33,1024,%d\n", i, i % 7);
    int rounds = 100;
    long long t0 = now_ns();
    long long total = 0;
    for (int r = 0; r < rounds; r++) {
        char *p = csv, *end = csv + off;
        while (p < end) {
            char *q;
            total += strtol(p, &q, 10);
            p = q + 1; /* past ',' or '\n' */
        }
    }
    long long elapsed = now_ns() - t0;
    printf("rounds=%d\ntotal=%lld\nelapsed_ns=%lld\n", rounds, total, elapsed);
    free(csv);
    return 0;
}
