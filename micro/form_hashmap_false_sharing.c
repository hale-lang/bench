// C equivalent of form_hashmap_false_sharing.hl.
// Two pthreads hammer disjoint keys (even / odd ids) of one shared
// hand-rolled open-addressing i64-keyed table behind a single
// pthread_mutex — the lock discipline of Hale's `sync = serialized`
// and the Go version's sync.Mutex. pthreads are real OS threads, so
// no LockOSThread analogue is needed. Throughput is bounded by
// contention; this is the safe-but-slow baseline all sides share.
#include <pthread.h>
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
    long long value;
} Counter;

// Open-addressing i64-keyed map: linear probing, 0.7 load factor,
// power-of-2 cap, grows by rehashing into a table twice the size.
typedef struct {
    long long key;
    Counter val;
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

static void map_set(Map *m, long long key, Counter val);

static void map_grow(Map *m) {
    Map bigger;
    map_init(&bigger, m->cap * 2);
    for (size_t i = 0; i < m->cap; i++) {
        if (m->slots[i].used) map_set(&bigger, m->slots[i].key, m->slots[i].val);
    }
    free(m->slots);
    *m = bigger;
}

__attribute__((noinline)) static void map_set(Map *m, long long key, Counter val) {
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

typedef struct {
    pthread_mutex_t mu;
    Map entries;
} Registry;

static void registry_set(Registry *r, Counter c) {
    pthread_mutex_lock(&r->mu);
    map_set(&r->entries, c.id, c);
    pthread_mutex_unlock(&r->mu);
}

static long long registry_len(Registry *r) {
    pthread_mutex_lock(&r->mu);
    long long n = (long long)r->entries.len;
    pthread_mutex_unlock(&r->mu);
    return n;
}

typedef struct {
    Registry *reg;
    long long per_writer;
    long long parity; // 0 → even ids, 1 → odd ids
} WriterArgs;

static void *writer_main(void *arg) {
    WriterArgs *a = arg;
    for (long long i = 0; i < a->per_writer; i++) {
        registry_set(a->reg, (Counter){.id = i * 2 + a->parity, .value = i});
    }
    return NULL;
}

int main(void) {
    long long per_writer = 100000;
    Registry reg;
    pthread_mutex_init(&reg.mu, NULL);
    map_init(&reg.entries, 16);

    WriterArgs a = {&reg, per_writer, 0}; // writer A — even ids
    WriterArgs b = {&reg, per_writer, 1}; // writer B — odd ids
    pthread_t ta, tb;

    long long t0 = now_ns();
    if (pthread_create(&ta, NULL, writer_main, &a) != 0) exit(1);
    if (pthread_create(&tb, NULL, writer_main, &b) != 0) exit(1);
    pthread_join(ta, NULL);
    pthread_join(tb, NULL);
    long long elapsed = now_ns() - t0;

    printf("per_writer=%lld\n", per_writer);
    printf("total=%lld\n", registry_len(&reg));
    printf("elapsed_ns=%lld\n", elapsed);
    free(reg.entries.slots);
    return 0;
}
