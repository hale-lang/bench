// C equivalent of json_parse.hl.
// Parses the same fixed market-data quote record N times and folds
// two fields. libc has no JSON parser, so this is a hand-rolled
// single-pass schema-specialized parse (key strings matched against
// the known Quote fields) — closer in spirit to Hale's generated
// Quote::from_json (Tier 2) than to Go's reflective encoding/json,
// so expect the C number to flatter C.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static long long now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000000000LL + (long long)ts.tv_nsec;
}

typedef struct {
    char sym[32];
    long long bid, ask, bidsz, asksz, ts, seq;
} Quote;

static const char *skip_ws(const char *p) {
    while (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r') p++;
    return p;
}

// Single-pass parse of a flat {"key": value, ...} object into Quote.
// Returns 0 on success, -1 on malformed input.
__attribute__((noinline)) static int quote_from_json(const char *s, Quote *q) {
    const char *p = skip_ws(s);
    if (*p++ != '{') return -1;
    for (;;) {
        p = skip_ws(p);
        if (*p++ != '"') return -1;
        const char *key = p;
        while (*p && *p != '"') p++;
        if (!*p) return -1;
        size_t klen = (size_t)(p - key);
        p++;
        p = skip_ws(p);
        if (*p++ != ':') return -1;
        p = skip_ws(p);
        if (*p == '"') { // string value
            p++;
            const char *v = p;
            while (*p && *p != '"') p++;
            if (!*p) return -1;
            size_t vlen = (size_t)(p - v);
            p++;
            if (klen == 3 && memcmp(key, "sym", 3) == 0) {
                if (vlen >= sizeof q->sym) return -1;
                memcpy(q->sym, v, vlen);
                q->sym[vlen] = '\0';
            }
        } else { // integer value
            int neg = 0;
            if (*p == '-') {
                neg = 1;
                p++;
            }
            if (*p < '0' || *p > '9') return -1;
            long long val = 0;
            while (*p >= '0' && *p <= '9') {
                val = val * 10 + (*p - '0');
                p++;
            }
            if (neg) val = -val;
            if (klen == 3 && memcmp(key, "bid", 3) == 0) q->bid = val;
            else if (klen == 3 && memcmp(key, "ask", 3) == 0) q->ask = val;
            else if (klen == 5 && memcmp(key, "bidsz", 5) == 0) q->bidsz = val;
            else if (klen == 5 && memcmp(key, "asksz", 5) == 0) q->asksz = val;
            else if (klen == 2 && memcmp(key, "ts", 2) == 0) q->ts = val;
            else if (klen == 3 && memcmp(key, "seq", 3) == 0) q->seq = val;
        }
        p = skip_ws(p);
        if (*p == ',') {
            p++;
            continue;
        }
        if (*p == '}') break;
        return -1;
    }
    return 0;
}

int main(void) {
    const char *body =
        "{\"sym\": \"BTCUSD\", \"bid\": 50000, \"ask\": 50010, \"bidsz\": 12, "
        "\"asksz\": 8, \"ts\": 1700000000000, \"seq\": 42}";
    long long iters = 200000;
    long long t0 = now_ns();
    long long total = 0;
    for (long long i = 0; i < iters; i++) {
        Quote q;
        if (quote_from_json(body, &q) != 0) exit(1);
        total += q.bid + q.ask;
    }
    long long elapsed = now_ns() - t0;
    printf("iters=%lld\n", iters);
    printf("total=%lld\n", total);
    printf("elapsed_ns=%lld\n", elapsed);
    return 0;
}
