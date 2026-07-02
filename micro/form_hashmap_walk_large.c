// C equivalent of form_hashmap_walk_large.hl.
// Pre-populate a hand-rolled open-addressing i64-keyed table
// (linear probing, 0.7 load factor, power-of-2 cap), then sweep the
// slot array summing values — the analogue of Hale's key_at /
// entry_at walk and Go's range-over-map. Iteration order is
// hash-table order everywhere; the comparison is
// throughput-per-entry, not order. Caveat: a flat slot sweep is
// friendlier to the prefetcher than Go's bucket chains.
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

static long long now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000000000LL + (long long)ts.tv_nsec;
}

typedef struct {
    long long id;
    long long val;
} Entry;

// Open-addressing i64-keyed map: linear probing, grows by rehashing
// into a table twice the size once load passes 0.7.
typedef struct {
    long long key;
    Entry val;
    unsigned char used;
} Slot;

typedef struct {
    Slot *slots;
    size_t cap, len;
} Map;

static unsigned long long hash_i64(long long k) {
    unsigned long long x = (unsigned long long)k;
    x ^= x >> 33; x *= 0xff51afd7ed558ccdULL;
    x ^= x >> 33; x *= 0xc4ceb9fe1a85ec53ULL;
    x ^= x >> 33;
    return x;
}

static void map_init(Map *m, size_t cap) {
    m->slots = calloc(cap, sizeof(Slot));
    if (!m->slots) exit(1);
    m->cap = cap;
    m->len = 0;
}

static void map_set(Map *m, long long key, Entry val);

static void map_grow(Map *m) {
    Map bigger;
    map_init(&bigger, m->cap * 2);
    for (size_t i = 0; i < m->cap; i++) {
        if (m->slots[i].used) map_set(&bigger, m->slots[i].key, m->slots[i].val);
    }
    free(m->slots);
    *m = bigger;
}

__attribute__((noinline)) static void map_set(Map *m, long long key, Entry val) {
    if ((m->len + 1) * 10 > m->cap * 7) map_grow(m);
    size_t i = hash_i64(key) & (m->cap - 1);
    while (m->slots[i].used && m->slots[i].key != key) i = (i + 1) & (m->cap - 1);
    if (!m->slots[i].used) {
        m->slots[i].used = 1;
        m->slots[i].key = key;
        m->len++;
    }
    m->slots[i].val = val;
}

// Smallest power of two holding n entries at <= 0.7 load.
static size_t cap_for(size_t n) {
    size_t cap = 16;
    while (n * 10 > cap * 7) cap *= 2;
    return cap;
}

int main(void) {
    long long n = 100000;
    Map m;
    map_init(&m, cap_for((size_t)n));
    for (long long i = 0; i < n; i++) {
        map_set(&m, i, (Entry){.id = i, .val = i * 3});
    }

    long long t0 = now_ns();
    long long sum = 0;
    for (size_t s = 0; s < m.cap; s++) {
        if (!m.slots[s].used) continue;
        long long k = m.slots[s].key;
        sum += m.slots[s].val.val + (k - k); // touch key + value, like Go's `range`
    }
    long long elapsed = now_ns() - t0;

    printf("n=%lld\n", n);
    printf("len=%lld\n", (long long)m.len);
    printf("sum=%lld\n", sum);
    printf("elapsed_ns=%lld\n", elapsed);
    free(m.slots);
    return 0;
}
