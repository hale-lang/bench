// C equivalent of ring_buffer_steady.hl — a fixed array ring; the tag is
// an inline char[16], how C would hold a short string in a record.
#include <stdio.h>
#include <string.h>
#include <time.h>

typedef struct { long t, v; char tag[16]; } Sample;

static Sample buf[64];
static int head = 0, size = 0;

static int push(const Sample *s) {
    if (size == 64) return 0;
    buf[(head + size) % 64] = *s;
    size++;
    return 1;
}

static int pop(Sample *out) {
    if (size == 0) return 0;
    *out = buf[head];
    head = (head + 1) % 64;
    size--;
    return 1;
}

static long long now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000000000LL + ts.tv_nsec;
}

int main(void) {
    long rounds = 2000000;
    long long t0 = now_ns();
    Sample s;
    for (long i = 0; i < 32; i++) {
        s.t = i; s.v = i % 7; snprintf(s.tag, sizeof s.tag, "s%ld", i % 10);
        push(&s);
    }
    long sum = 0;
    for (long k = 0; k < rounds; k++) {
        s.t = k; s.v = k % 7; snprintf(s.tag, sizeof s.tag, "s%ld", k % 10);
        push(&s);
        Sample got;
        if (!pop(&got)) { got.v = 0; got.tag[0] = 0; }
        sum += got.v + (long)strlen(got.tag);
    }
    long long elapsed = now_ns() - t0;
    printf("rounds=%ld\nsum=%ld\nelapsed_ns=%lld\n", rounds, sum, elapsed);
    return 0;
}
