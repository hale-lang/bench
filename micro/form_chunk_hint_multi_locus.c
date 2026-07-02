// C equivalent of form_chunk_hint_multi_locus.hl.
// 16 workers subscribed to one subject; 1000 published ticks fan
// out to all 16 (16000 handler invocations), mirroring the .hl's 16
// cooperative loci on one io pool. Caveat: the .hl exists to
// exercise F.32-3 per-pool arena chunk-size hints and its timed
// region includes a 200ms drain sleep; C dispatch is synchronous
// and arena-free, so elapsed_ns is not comparable — only the
// workload shape (and the per-worker "alive" lines) is mirrored.
#include <stdio.h>
#include <time.h>

static long long now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000000000LL + (long long)ts.tv_nsec;
}

#define NUM_WORKERS 16

typedef struct {
    long long id;
    long long tally;
} Worker;

static void worker_on_tick(Worker *w, long long n) {
    w->tally++;
    if (n == 0) {
        printf("worker %lld alive\n", w->id);
    }
}

int main(void) {
    Worker workers[NUM_WORKERS];
    for (long long i = 0; i < NUM_WORKERS; i++) {
        workers[i].id = i;
        workers[i].tally = 0;
    }

    long long n_ticks = 1000;
    long long t0 = now_ns();
    for (long long i = 0; i < n_ticks; i++) {
        // One publish → delivery to every subscriber on the subject.
        for (long long w = 0; w < NUM_WORKERS; w++) {
            worker_on_tick(&workers[w], i);
        }
    }
    long long t1 = now_ns();

    printf("n_ticks=%lld\n", n_ticks);
    printf("workers=%d\n", NUM_WORKERS);
    printf("elapsed_ns=%lld\n", t1 - t0);
    return 0;
}
