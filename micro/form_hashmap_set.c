// C equivalent of form_hashmap_set.hl.
// N inserts into a hand-rolled open-addressing i64-keyed table
// (linear probing, 0.7 load factor, power-of-2 cap, grow by rehash)
// — same big-O and layout family as Hale's @form(hashmap); Go uses
// chained buckets instead. Caveat: the splitmix64-style mixer
// stands in for Go's AES-based runtime hash.
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
    long long v;
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

// noinline: keep the insert a real call, like Go's mapassign.
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

int main(void) {
    long long n = 1000000;
    Map m;
    map_init(&m, 16);
    long long t0 = now_ns();
    for (long long i = 0; i < n; i++) {
        map_set(&m, i, (Entry){.id = i, .v = i + 1});
    }
    long long elapsed = now_ns() - t0;
    printf("n=%lld\n", n);
    printf("len=%lld\n", (long long)m.len);
    printf("elapsed_ns=%lld\n", elapsed);
    free(m.slots);
    return 0;
}
