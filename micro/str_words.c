// C equivalent of str_words.hl — a hand-written whitespace scan (C has
// no split; this is what a C program would write).
#include <ctype.h>
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
    const char *s = "the quick brown fox jumps over a lazy dog and runs ";
    size_t sl = strlen(s);
    char *text = malloc(sl * 200 + 1);
    for (int i = 0; i < 200; i++) memcpy(text + i * sl, s, sl);
    text[sl * 200] = 0;
    size_t tl = sl * 200;
    int rounds = 500;
    long long t0 = now_ns();
    long n = 0;
    for (int r = 0; r < rounds; r++) {
        size_t i = 0;
        while (i < tl) {
            while (i < tl && isspace((unsigned char)text[i])) i++;
            size_t start = i;
            while (i < tl && !isspace((unsigned char)text[i])) i++;
            if (i > start && i - start > 3) n++;
        }
    }
    long long elapsed = now_ns() - t0;
    printf("rounds=%d\ncount=%ld\nelapsed_ns=%lld\n", rounds, n, elapsed);
    free(text);
    return 0;
}
