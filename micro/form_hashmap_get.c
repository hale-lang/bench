// C equivalent of form_hashmap_get.hl.
// Populate (outside timing, pre-sized like Go's make(map, n)) then
// N lookups on a hand-rolled open-addressing i64-keyed table
// (linear probing, 0.7 load factor, power-of-2 cap). map_get
// returning NULL-on-missing is the analog of Hale's
// `m.get(k) or raise`; every key is present in this bench.
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

// noinline: keep the lookup a real call, like Go's mapaccess.
__attribute__((noinline)) static Entry *map_get(Map *m, long long key) {
    size_t i = hash_i64(key) & (m->cap - 1);
    while (m->slots[i].used) {
        if (m->slots[i].key == key) return &m->slots[i].val;
        i = (i + 1) & (m->cap - 1);
    }
    return NULL;
}

// Smallest power of two holding n entries at <= 0.7 load.
static size_t cap_for(size_t n) {
    size_t cap = 16;
    while (n * 10 > cap * 7) cap *= 2;
    return cap;
}

int main(void) {
    long long n = 150000;
    Map m;
    map_init(&m, cap_for((size_t)n));
    for (long long i = 0; i < n; i++) {
        map_set(&m, i, (Entry){.id = i, .v = i + 1});
    }

    long long t0 = now_ns();
    long long acc = 0;
    for (long long j = 0; j < n; j++) {
        Entry *e = map_get(&m, j);
        if (!e) exit(1);
        acc += e->v;
    }
    long long elapsed = now_ns() - t0;
    printf("n=%lld\n", n);
    printf("acc=%lld\n", acc);
    printf("elapsed_ns=%lld\n", elapsed);
    free(m.slots);
    return 0;
}
