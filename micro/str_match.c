// C equivalent of str_match.hl — an strcmp chain (C has no string switch).
#include <stdio.h>
#include <string.h>
#include <time.h>

static long long now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000000000LL + ts.tv_nsec;
}

static const char *ARMS[16] = {"alpha", "bravo", "charlie", "delta", "echo",
    "foxtrot", "golf", "hotel", "india", "juliett", "kilo", "lima", "mike",
    "november", "oscar", "papa"};

__attribute__((noinline)) static long arm(const char *w) {
    for (int k = 0; k < 16; k++)
        if (strcmp(w, ARMS[k]) == 0) return k + 1;
    return 0;
}

int main(void) {
    const char *words[17] = {"alpha", "bravo", "charlie", "delta", "echo",
        "foxtrot", "golf", "hotel", "india", "juliett", "kilo", "lima", "mike",
        "november", "oscar", "papa", "quebec"};
    long iters = 2000000;
    long long t0 = now_ns();
    long sum = 0;
    for (long i = 0; i < iters; i++) sum += arm(words[i % 17]);
    long long elapsed = now_ns() - t0;
    printf("iters=%ld\nsum=%ld\nelapsed_ns=%lld\n", iters, sum, elapsed);
    return 0;
}
