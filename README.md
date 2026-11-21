# Hale benchmark suite

> Baselines current as of hale **v0.36.0** (main 1e4fd190d,
> 2026-11-19), rebuilt from 5 independent runs x 21 iters with
> per-bench tolerance bands derived from measured noise — see
> **Tolerance bands** below. Every bench is built `--target-cpu native`
> whatever `hale build`'s default. The cross-language comparative grid,
> the cross-process SHM tables and the v1 gate measures further down
> were re-run on the same build the same day. What moved since the
> previous baselines (v0.32.7) and why: **Since v0.32.7**, below. The
> benches added later that day (text, bounded lists, the ring buffer,
> `@rpc` and `ws::Hub`, startup, Postgres and the unix-socket bus) were
> first measured on the same build.

Performance harness for Hale, comparing against Go / Node / Python
sibling implementations of the same workload shape. For the language
itself, see [hale-lang/hale](https://github.com/hale-lang/hale).
Baseline scaffold for Layer 3 (performance) per `spec/testing.md` in
the hale repo.
Microbenches isolate substrate primitives; one app-level bench
exercises a small mixed workload end-to-end; `gates/` measures the
toolchain and a served program (build time, HTTP serving, a server's
memory under load, editor latency — see **v1 gate measures**). The
runner is shell + jq, no extra build dependencies.

Each `.hl` bench ships with sibling `.go`, `.js`, and `.py`
equivalents implementing the same shape as closely as possible.
The harness runs all of them, reports per-language medians plus
a `ratio_vs_hale` column, but **only Hale regressions** gate
exit code (per `spec/testing.md` Layer 3: "a regression in
hale-vs-X ratio is a developer signal, not a CI gate").

## Quickstart

```
# From repo root, with the CLI built (cargo build --release -p hale-cli):
./run.sh                       # run all + comparatives, exit 1 on Hale regression
./run.sh --iters=10            # more samples per bench (default 5)
./run.sh --bench=loop_overhead # one bench at a time
./rebaseline.sh                # rebuild baselines.json (5 runs x 21 iters)
./rebaseline.sh 5 31           # more runs / more iters
./run.sh --no-build            # skip rebuild step
./run.sh --no-comparative      # Hale only, skip go/node/python siblings
./run.sh --json                # emit only the JSON report to stdout
gates/run.sh                   # the v1 gate measures (build, http, memory, lsp, api, hub, startup, pg), ~16 min
gates/run.sh --record          # ... and record them in baselines.json's "gates"
```

Each invocation writes a timestamped JSON report under
`results/` (gitignored).

## Tolerance bands

A band is a claim about what the harness can **resolve**, so it is
derived from measurement rather than picked.

It used to be a per-bench constant defaulting to `0.30`, which
`--update-baselines` carried forward verbatim — so it never tracked
anything. `fn_modular` pins its median to ~1.4% and had a 30% band: a
real **29% regression passed the gate with a point to spare and
survived five releases** ([hale#522][522]).

Two noise terms are recorded per bench, because there are two
independent sources and the smaller one is the tempting place to stop:

| term | what it is | this suite |
|---|---|---|
| `noise` | within-run standard error of the median — how well ONE run pins its own number | 0.0 – 3.9% |
| `drift_sigma` | between-run movement of that median on an **unchanged** binary, as an estimated σ | 0.0 – 4.1% |

`drift_sigma` is `range / d2(N)`, not the raw range. The range of N
samples understates spread badly at small N (`d2(3)` is only 1.69), and
recording it raw from 3 runs produced bands up to **4x too tight** on
the noisiest benches — they fired on the very next sweep of the same
binary. The `d2` correction makes the estimate unbiased at any N, so
more runs buy precision rather than fixing a systematic error.

Drift usually dominates. It is machine state — thermal, page cache,
whatever else was running — and a single run cannot see any of it,
because every sample inside a run shares it. Building bands from
`noise` alone produced **three false regressions against the very
binary they were baselined on**, which is why `rebaseline.sh` exists
and `run.sh --update-baselines` now refuses.

    band = clamp(4 x max(noise, drift_sigma), 0.05, 0.35)

The floor stops an unusually quiet run from producing a band that
ordinary jitter trips. The ceiling is an honesty limit: past it a
bench cannot resolve a regression at all, and the run-time guard
reports INCONCLUSIVE rather than guessing.

Current bands run 5% – 16%, median 5%. Set `tolerance_override` on a
bench in `baselines.json` to pin one by hand, with a comment saying
why.

### A baseline is only valid for comparable machine conditions

This is a real limit, not a rough edge to file off. Drift is machine
state, so it is a property of *the machine while measuring*, not of
the bench. The same `bus_dispatch_heap_payload` measured **21% drift**
across sweeps interleaved with heavy `cargo build`s and **1.1%** on a
quiet machine an hour later — a 19x difference in the number the band
is derived from.

Practical consequences:

- **Re-baseline on the machine and under the conditions you will
  check on.** A quiet-machine baseline checked under load produces
  false regressions; the reverse hides real ones.
- **A regression on a busy machine is a reason to re-run, not to
  believe.** The INCONCLUSIVE verdict catches the case where this
  run cannot resolve its own median, but it cannot catch a run that
  is internally consistent and globally shifted.
- **Do not treat these bands as portable across machines.** They are
  not, and `baselines.json` records the `hale_version` it measured
  but has no way to record the machine.

**Validated both directions** on the day it landed: four full passes
against the baselined binary reported zero regressions and zero
inconclusives, while v0.18.0 (which carries #522) was caught and
v0.13.0 (which predates it) passed clean.

Four passes rather than two on purpose — an earlier two-pass check
passed and the change still false-fired afterwards, because both
passes happened to land in the same cluster of a bimodal bench.

[522]: https://github.com/hale-lang/hale/issues/522

## Reproducing the comparative grid

Exact steps, from nothing:

```sh
# 1. Build the Hale CLI (needs Rust 1.95+, LLVM 18, clang):
git clone https://github.com/hale-lang/hale
cd hale && cargo build --release -p hale-cli && cd ..

# 2. Clone this repo as a sibling (run.sh finds ../hale/target/release/hale,
#    or set HALE_BIN=/path/to/hale):
git clone https://github.com/hale-lang/bench
cd bench

# 3. Have the comparison toolchains on PATH: go, node, python3.
#    Any that are missing are silently skipped.

# 4. Run everything (5 samples per bench, medians reported):
./run.sh

# One bench, more samples:
./run.sh --bench=bus_dispatch --iters=10

# The C / Rust comparator sweep needs clang and rustc on PATH;
# the cross-process SHM benches are separate:
xproc/run.sh
```

The per-bench `ratio_vs_hale` lines printed by `run.sh` (and written
to `results/run-<stamp>.json`) are the numbers in the grid below.
Numbers move meaningfully between machines — compare ratios from
*your* run, not absolute times against the snapshot's Ryzen 9800X3D.

## Since v0.32.7

The previous baselines were taken on hale main 25fe52518 (v0.32.7,
2026-11-07). Against **their** tolerance bands, the v0.36.0 baselines
(5 runs x 21 iters) put four benches out of band. All four are slower,
and all four come from one change:

| Bench | v0.32.7 | v0.36.0 | Δ | Band | Cause |
|---|---:|---:|---:|---:|---|
| `loop_overhead` | 1.86 ms | 19.99 ms | +974% | 10.1% | hale#1874's drain latch on every loop back-edge in `fn main`: the per-iteration atomic load keeps the XOR reduction from vectorizing ([hale#2089](https://github.com/hale-lang/hale/issues/2089)) |
| `form_vec_get` | 13.3 µs | 42.0 µs | +217% | 14.1% | the same; its read loop is in `fn main` (hale#2089) |
| `form_hashmap_walk_large` | 114.5 µs | 123.1 µs | +7.5% | 5.0% | the latch's own cost on the walk loop in `run()` |
| `stream_aggregator` | 435.7 µs | 466.1 µs | +7.0% | 6.2% | the latch's own cost on the publisher's `run()` loop |

**How it was placed.** Each bench built by the v0.32.7 release, by
hale at the merge of hale#1874 (168ac285b) and at its first parent, and
by every release since; interleaved runs, the median of 7 (first two
rows) or 11 (last two):

| Bench | v0.32.7 | #1874^1 | #1874 | v0.33.0 | v0.34.0 | v0.35.0 | v0.36.0 |
|---|---:|---:|---:|---:|---:|---:|---:|
| `loop_overhead` | 1.71 ms | 1.65 ms | 20.0 ms | | | | 20.0 ms |
| `form_vec_get` | 11.4 µs | 11.2 µs | 41.9 µs | | | | 43.8 µs |
| `form_hashmap_walk_large` | 118.3 µs | 115.8 µs | 121.3 µs | 119.1 µs | 118.0 µs | 120.1 µs | 120.5 µs |
| `stream_aggregator` | 439.0 µs | 439.9 µs | 460.9 µs | 460.6 µs | 457.9 µs | 466.7 µs | 469.9 µs |

The step is at hale#1874 and nowhere else. Since that change (GH #1858),
a SIGTERM ends every loop in `fn main` and in a `run()` that does not
read `draining` between two iterations, so the program runs its
`drain()` / `dissolve()` hooks and exits 0. Each such loop ends its
iteration at a latch: a monotonic load of the process's drain flag and
a cold branch to the exit. The disassembly shows it: at v0.36.0,
`loop_overhead`'s loop is `xor` / `inc` / a load of
`lotus_process_draining_flag`, where before it was the AVX-512
reduction. The same loop in a plain `fn` has no latch and still
vectorizes (2.3 ms on v0.36.0).

**Expected?** The latch is by design, and so is a few percent on a loop
that does real work (the last two rows). The lost vectorization was not
considered when it landed; it is
[hale#2089](https://github.com/hale-lang/hale/issues/2089), with
strip-mining the check (once per K iterations) as the likely fix. These
baselines carry the cost, so a fix will show here as an improvement.

**Everything else is inside its band.** The largest in-band moves are
`form_vec_push` +12.8% (band 20.8%) and `vec_amortized` +5.1% (band
35%). The range's other runtime changes, the ones a bench could have
seen, move nothing out of band: bounded-value copies and retirement
(hale#1905, #1919, #1961), linear string building (#1960), O(1) string
`len` (#2018), ring-buffer push without a copy (#2044) and the `let`
write rules (#2055). No existing bench exercises most of those shapes
directly.

**maxrss** is about 10% (≈0.5 MB) lower on nearly every bench. That is
not a hale change. The baseline's own commit, 25fe52518, rebuilt and
run today, gives `stream_aggregator` 4.26 MB against the 4.98 MB
recorded on 2026-11-07, so the same compiler measures lower on today's
machine state. maxrss is not gated.

**Cross-process SHM (`xproc/`)** has no baseline file. v0.32.7 and
v0.36.0 run back to back give the same numbers within noise (small:
per-record 12.55 / 12.31 ms, `Drain<T>` 2.80 / 2.80 ms; large: 18.20 /
19.22 ms, 20.51 / 20.84 ms).

**New since then:** `bus_round_trip`, `bus_round_trip_cross_pool` and
`json_encode` (added on v0.36.0, now baselined with the full suite)
and the v1 gate measures under `gates/`, which are measured only.

## Cross-language comparative grid

Latest snapshot: **hale v0.36.0** (main 1e4fd190d), 2026-11-19, AMD
Ryzen 7 9800X3D / x86_64 / Linux 6.18.
Toolchains: Go 1.25.5, Node v25.2.1, Python 3.12.3. One `./run.sh
--iters=11`, every Hale bench built `--target-cpu native`; each cell
is the median.

Read each cell as `<elapsed> (<ratio_vs_hale>×)` where
**ratio = sibling_time / hale_time**:

- ratio > 1 → sibling is **slower** than Hale by that factor.
- ratio < 1 → sibling is **faster** than Hale by 1/ratio.
- `—` → no sibling exists for this bench (Hale-only).

### Overhead microbenches

| Bench | Hale | Go | Node | Python |
|---|---:|---:|---:|---:|
| `loop_overhead` \*          | 20.03 ms | 19.52 ms (0.975×) | 20.64 ms (1.03×) | 3.48 s (174×) |
| `fn_call`                   | 11.48 ms | 7.68 ms (0.669×) | 4.38 ms (0.381×) | 509.83 ms (44.4×) |
| `fn_modular`                | 17.27 ms | 15.34 ms (0.888×) | 3.99 ms (0.231×) | 615.81 ms (35.7×) |
| `locus_instantiation`       | 1.79 ms | 152.81 µs (0.0855×) | 983.69 µs (0.550×) | 12.41 ms (6.94×) |
| `bus_dispatch`              | 173.41 µs | 464.39 µs (2.68×) | 1.25 ms (7.21×) | 11.00 ms (63.4×) |
| `bus_dispatch_heap_payload` | 1.98 ms | — | — | — |
| `bus_publish_shm_ring`      | 1.39 ms | — | — | — |
| `bus_round_trip`            | 6.88 ms | — | — | — |
| `form_vec_push`             | 721.45 µs | 2.52 ms (3.49×) | 3.57 ms (4.95×) | 12.89 ms (17.9×) |
| `form_vec_get`              | 40.58 µs | 39.28 µs (0.968×) | 658.86 µs (16.2×) | 7.76 ms (191×) |
| `form_hashmap_set`          | 39.83 ms | 49.02 ms (1.23×) | 80.34 ms (2.02×) | 256.88 ms (6.45×) |
| `form_hashmap_get`          | 1.16 ms | 1.07 ms (0.926×) | 2.51 ms (2.17×) | 9.16 ms (7.92×) |
| `json_parse`                | 63.60 ms | 142.74 ms (2.24×) | 50.89 ms (0.800×) | 223.19 ms (3.51×) |
| `json_encode`               | 63.56 ms | 31.80 ms (0.500×) | 18.06 ms (0.284×) | 327.01 ms (5.15×) |

\* `loop_overhead` is not a dead-code artifact — every sibling
xor-accumulates into a pid-seeded value that's printed, so no side can
eliminate the loop (verified in the sources: `micro/loop_overhead.go`
keeps the loop; Hale's own codegen *would* fold a pure loop, which is
why the bench was reshaped). Through v0.32.7 Hale led Go 11× here, and
that was an **autovectorization win, not loop-construct overhead**:
LLVM vectorized the XOR reduction to AVX-512 while Go's compiler emits
a scalar loop (~0.02 ns/iter vs ~0.2 ns/iter). Since hale#1874 (v0.33.0)
every loop in `fn main` and in a `run()` ends each iteration at a load
of the process's drain flag, so the loop can be stopped between
iterations on SIGTERM; that per-iteration atomic load keeps LLVM from
vectorizing it, and the bench is now at parity with Go
([hale#2089](https://github.com/hale-lang/hale/issues/2089)). The same
loop in a plain `fn` still vectorizes (2.3 ms). `form_vec_get` is the
same story (3× ahead of Go through v0.32.7, parity now).

`json_parse` is 200k parses of a 7-field market-data quote
via the inlined `Type::from_json`. Hale **beats Go's
encoding/json 2.24× and Python's json.loads 3.51×**, and
sits ~20% behind V8's `JSON.parse` (0.800×).

`json_encode` is the other direction on the same record, 200k
`Type::to_json` encodes. There Hale is behind: Go's encoding/json is
2.0× faster and V8's `JSON.stringify` 3.5×. Its maxrss (72 MB, against
`json_parse`'s 29 MB) says the encoded strings are held until `main`
returns rather than freed each iteration.

`bus_round_trip` is a request/reply latency: 200k Ping → Pong round
trips with one in flight, about 34 ns each, where `bus_dispatch`
pipelines one-way publishes at about 1.7 ns each.

### Amortized microbenches

| Bench | Hale | Go | Node | Python |
|---|---:|---:|---:|---:|
| `vec_amortized`     | 335.49 µs | 1.23 ms (3.67×) | 2.93 ms (8.72×) | 13.60 ms (40.5×) |
| `fn_scratch_work`   | 60.02 µs | 439.54 µs (7.32×) | 940.81 µs (15.7×) | 2.66 ms (44.3×) |
| `coord_with_churn`  | 39.34 µs | 2.05 µs (0.0522×) | 113.96 µs (2.90×) | 138.04 µs (3.51×) |

### Per-iteration reclaim microbenches

| Bench | Hale | Go | Node | Python |
|---|---:|---:|---:|---:|
| `method_loop_alloc` | 229.72 ms | 124.83 ms (0.543×) | 104.09 ms (0.453×) | 460.63 ms (2.01×) |

`method_loop_alloc` holds its memory flat (maxrss 4.5 MB) because the
loop body gets an arena per iteration (hale-lang/hale#1765). The same
loop under v0.29.0 peaked at about 317 MB and ran about 17% slower. The
remaining gap to Go and Node is the cost of `to_string` plus the arena
enter/leave pair (about 60 instructions an iteration), not
accumulation.

### Text, bounded-list and ring microbenches

| Bench | Hale | Go | Node | Python |
|---|---:|---:|---:|---:|
| `str_words`          | 24.29 ms | 7.61 ms (0.313×) | 15.85 ms (0.653×) | 53.69 ms (2.21×) |
| `str_words_chain`    | 24.31 ms | — | — | — |
| `str_csv_sum`        | 69.35 ms | 7.45 ms (0.107×) | 30.87 ms (0.445×) | 57.94 ms (0.835×) |
| `str_concat_loop`    | 5.73 ms | 2.17 ms (0.378×) | 17.13 ms (2.99×) | 17.49 ms (3.05×) |
| `str_match`          | 60.50 ms | 2.92 ms (0.0482×) | 4.27 ms (0.0706×) | 190.08 ms (3.14×) |
| `display_template`   | 50.48 ms | — | — | — |
| `display_fstring`    | 38.92 ms | — | — | — |
| `bounded_records`    | 98.71 ms | 71.45 ms (0.724×) | 34.97 ms (0.354×) | 263.38 ms (2.67×) |
| `ring_buffer_steady` | 105.89 ms | 27.45 ms (0.259×) | 24.54 ms (0.232×) | 215.82 ms (2.04×) |

Added 2026-11-19, first measured on v0.36.0. Text is the weakest area
this suite measures:

- **Splitting and parsing.** Go splits words 3.2× faster and parses
  the CSV 9× faster; C and Rust are 10–27× faster on both.
- **String `match`.** 16 literal arms cost about 30 ns a match, where
  Go's and Rust's `switch` / `match` cost about 1.5 ns and C's `strcmp`
  chain 12 ns.
- **Chains.** `str_words_chain` times the same as the `for` loop over
  `words`, so the chain costs nothing beyond the loop.
- **Building with `+`.** A string built with `+` is linear
  (hale-lang/hale#1960): 5.7 ns an append, against 2.2 ns for Go's
  `strings.Builder` and 0.5 ns for a C doubling buffer.
- **`@display`.** A template renders 30% slower than the f-string it
  stands for (hale-lang/hale#2061 desugars one to the other), and both
  hold 59–67 MB at the end, because what `fn main`'s loop makes stays
  until `main` returns (see hale-lang/hale#2090).

`bounded_records` is ahead of Rust (1.11×, which clones where Hale
copies) and Python, and behind Go (whose struct copies share their
immutable strings) and V8. `ring_buffer_steady` holds 4.5 MB flat over
2M push/pop rounds, while C and Rust are about 2.4× faster.

### Coordinated-workload microbenches

| Bench | Hale | Go | Node | Python |
|---|---:|---:|---:|---:|
| `tree_fanout`      | 24.56 µs | 8.01 µs (0.326×) | 226.22 µs (9.21×) | 574.65 µs (23.4×) |
| `pipeline_3stage`  | 2.23 ms | 214.93 µs (0.0966×) | 1.13 ms (0.506×) | 6.98 ms (3.14×) |

### Cross-pool / cache microbenches (F.32)

| Bench | Hale | Go | Node | Python |
|---|---:|---:|---:|---:|
| `bus_dispatch_cross_pool` † | 5.70 ms | 6.11 ms (1.07×) | 38.95 ms (6.83×) | 84.52 ms (14.8×) |
| `form_hashmap_false_sharing`  | 20.44 ms | 9.87 ms (0.483×) | 85.89 ms (4.20×) | 36.43 ms (1.78×) |
| `form_hashmap_walk_large`     | 123.62 µs | 381.18 µs (3.08×) | 749.87 µs (6.07×) | 7.32 ms (59.2×) |
| `bus_round_trip_cross_pool`   | 161.30 ms | — | — | — |

† `bus_dispatch_cross_pool` has been bimodal from run to run on this
host: its median lands near 5.1 ms or near 6.2 ms. The current baseline,
a median of five runs, is 5.31 ms with an 8% band; this snapshot's
5.70 ms puts Hale 1.07× ahead of Go, and in the fast mode it is about
1.2× ahead.

`form_hashmap_false_sharing` exercises the F.32-1γ-v2
`sync = lockfree` discipline (cell-level CAS on the
steady-state hot path; `remove` via tombstones; transparent
grow when load factor exceeds 0.6). When it shipped, lockfree
closed the gap with Go's sync.Mutex map on this 2-core /
cheap-payload bench from 1.66× (under α serialized) to 1.18×;
on this snapshot Go is 2.1× ahead (0.483×).
The annotation chain shows the F.32-1 alternatives in
order of measured perf on this hardware: γ-v2 (lockfree) >
α (serialized) > β2-v2 (striped+rwlock). On higher-core-
count hardware or heavier per-op work, the ordering
shifts; see `notes/f32-cache-aware-delivery-plan.md` §
F.32-1 for the per-discipline trade-off table.

Note: F.32-1γ-v2 (2026-05-26) added `remove` (via 4-state
tombstone machine) and lazy grow (single-grower migration
with brief writer/reader stall) to the lockfree
discipline. The hot-path cost change is small enough to
sit inside the per-bench tolerance band — `form_hashmap_set`
moved from 41.30 ms → ~45 ms (∼9% slower) trading off the
new load-factor check on every insert; `form_hashmap_get`
moved from 5.75 ms → 5.90 ms (∼3% faster vs v0.8.0; held
roughly steady after substrate-race fixes) from the
tombstone-aware probe + the lf_enter atomic-load fast
path replacing the previous code's separate len-check.

A substrate-race-fix pass (bus queue multi-thread flag,
arena subregion mutex, pthread_once on env-var helpers)
briefly added correctness cost to the bus-dispatch hot path
— `lotus_bus_queue_drain` always takes its mutex under a
cooperative pool worker, fixing a silent head/tail race
(the v0.8.1 grid caught this as `bus_dispatch` 8.87 → 9.59
ms). **GH #125 has since more than recovered it:** bounding
the cooperative bus queue (default 8192-cell cap) replaced
the unbounded backlog with a far more cache-friendly fixed
ring, cutting both latency and resident memory across the
bus family. Net vs the v0.8.1 snapshot: `bus_dispatch`
9.59 → 2.82 ms, `bus_dispatch_heap_payload` 5.15 → 2.08 ms
(maxrss 31 → 10 MB), `stream_aggregator` 19.50 → 5.26 ms
(maxrss 110 → 9.7 MB). `bus_dispatch_cross_pool` runs the
other way — ~11 → 25 ms — a correctness-driven increase
(per-thread-correct wire dispatch + the per-arena subregion
lock), within its widened 0.40 tolerance at the time.

**Method-scratch elision (2026-06-28).** The compiler now skips the
per-call scratch-arena `malloc`/`free` for a locus method / bus handler
/ `birth()` that provably allocates nothing and returns a by-value
scalar (or Unit) — see the `fn_call` / `fn_modular` notes above for the
free-fn analog. Because a bus handler and a `birth()` are methods, this
cut the method-heavy benches again on top of the bounded-queue win:
`bus_dispatch` 2.82 → 1.79 ms, `bus_dispatch_heap_payload` 2.08 →
1.51 ms, `bus_dispatch_cross_pool` 25 → 10.7 ms, and
`locus_instantiation` 2.45 → 1.25 ms (`Empty {}`'s `birth()` is now
scratch-free). Re-baselined.

**Lock-free bus + static dispatch devirtualization (v0.9.0).** The pinned-locus
mailbox and cooperative-pool queues became lock-free MPSC rings (genmc-verified),
and statically-eligible local subjects skip the runtime dispatch entirely — a
*quiet* same-thread handler is lowered to a direct synchronous call (differential-
verified equal to the dynamic path). The bus stopped being the weak spot:
`bus_dispatch` 1.79 → 0.196 ms (then 2.4× ahead of Go, was ~4× behind),
`bus_dispatch_cross_pool` 10.7 → 5.03 ms (then 1.26× ahead, was 1.6× behind),
`stream_aggregator` 5.26 ms → 436 µs (~23× behind Go → 1.9×),
`pipeline_3stage` 3.89 → 1.57 ms. Footprint trade-off: the lock-free rings
pre-allocate their cap (~4.3 MB per pinned mailbox / cooperative pool at the
default 8192) instead of growing — down-tunable via `LOTUS_BUS_QUEUE_CAP`.
Re-baselined at the time under v0.9.0; `baselines.json` has since been
re-baselined (its `hale_version` field names the binary the current
medians came from — v0.36.0, main 1e4fd190d, as of 2026-11-19).

### App benches

| Bench | Hale | Go | Node | Python |
|---|---:|---:|---:|---:|
| `stream_aggregator`  | 474.77 µs | 233.11 µs (0.491×) | 1.57 ms (3.31×) | 30.93 ms (65.1×) |

### Cross-process SHM delivery (`xproc/`)

**Separate from the main grid above.** This bench lives entirely
under `xproc/` and is **not** run by the top-level `run.sh`; run it
with `xproc/run.sh`. It measures *end-to-end cross-process zero-copy
shared-memory delivery throughput*: a PRODUCER process floods N fixed
records into a shared-memory ring sized to hold all N without wrap
(no drops), and a READER process times wall-clock from the first
record to the last, printing `elapsed_ns`. All timing is on the
reader's one clock, so no cross-process clock sync is needed. This is the cross-process counterpart to the
single-process `bus_publish_shm_ring` microbench (which measures
publish-in-isolation and unfairly favors bare in-process array
writes — a different question).

There are **two variants** (run both with `xproc/run.sh`):

- **small** — N = 200 000 fixed 16-byte records (two int64s). This
  is *dispatch-bound*: the payload is so small that copy-vs-zero-copy
  is noise, so per-record delivery cost dominates.
- **large** — N = 20 000 ~4 KB records (512 int64s); the reader does
  real work on the **whole** payload (sums all 512 fields into a
  checksum that's asserted against an expected value). This is
  *copy-bound*: where a copy-based reader would eat a 4 KB memcpy per
  record, so it's where zero-copy read should pay off.

Snapshots (hale v0.36.0, main 1e4fd190d, 2026-11-19; AMD Ryzen 7
9800X3D / x86_64 / Linux 6.18; `ITERS=20 xproc/run.sh`, median of 20
runs):

**small — N = 200 000, 16-byte records**

| language | median | ratio_vs_hale |
|---|---:|---:|
| **Hale** — per-record handler | 12.31 ms | 1.00× |
| **Hale** — `Drain<T>` batch | **2.80 ms** | **0.23×** |
| Go | 3.20 ms | 0.26× |
| Node | 10.28 ms | 0.84× † |
| Python | 30.40 ms | 2.47× |

**large — N = 20 000, ~4 KB records (reader sums whole payload)**

| language | median | ratio_vs_hale |
|---|---:|---:|
| **Hale** — per-record handler | 19.22 ms | 1.00× |
| **Hale** — `Drain<T>` batch | 20.84 ms | 1.08× |
| Go | 17.82 ms | 0.93× |
| Node | 103.60 ms | 5.39× † |
| Python | 335.10 ms | 17.43× |

The small per-record row is the noisiest here: its median moves
between about 10 and 12.5 ms from one 10–20-run invocation to the next
on an unchanged binary. The earlier snapshot of these tables (per-record
10.80 / `Drain<T>` 2.29 ms small, 33.98 / 34.36 ms large) was taken
before v0.32.7 and carried no version; v0.32.7 already measures
12.55 / 2.80 ms and 18.20 / 20.51 ms, the same as v0.36.0 within noise,
so the large-variant gain predates the range **Since v0.32.7** covers.

**Bus over `unix://`** (`xproc/run-unix-bus.sh`, run at the end of
`xproc/run.sh`, Hale-only). The bus itself bound across two processes:
a publisher floods N = 200 000 one-Int records on a topic that
`LOTUS_BUS_CONFIG` binds to a unix socket the subscriber listens on, and
the subscriber times its first delivery to its last. The code of both
is what it would be in one process. Median of 20 runs, v0.36.0:

| mode | median | records/s |
|---|---:|---:|
| default binding | 135.03 ms | 1,481,212 |
| `LOTUS_UNIX_STREAM=1` (framed stream) | 185.82 ms | 1,076,328 |

**The `Drain<T>` batch consumer closes the dispatch gap — and on the
small variant, Hale now wins.** A subscriber whose handler takes
`Drain<T>` instead of the payload `T` is dispatched **once per
available batch**; it consumes records in a tight inline `for t in
feed` loop with no per-record function call and no per-call arena
scratch:

```hale
bus { subscribe Tick as on_batch; }            // same binding line
fn on_batch(feed: Drain<TickPayload>) {
    for t in feed { /* read t.px in place, zero-copy */ }
}
```

The per-record handler dispatch (one call + one arena scratch *per
record*) was the *entire* structural edge the bare-loop siblings had —
the ring read itself was already zero-copy (verified below). Removing
it takes the small / dispatch-bound reader from 12.31 ms to **2.80 ms:
4.4× faster, and past Go's 3.20 ms.** That's the idiomatic Hale
consumer — a declarative `subscribe` plus an inline loop, no hand-rolled
mmap walk — so it's an apples-to-apples win on *both* ergonomics and raw
throughput. (`hale_drain` in `xproc/run.sh`; the per-record row is kept
for contrast.)

On the **large / copy-bound** variant the batch form does not help
(1.08×, a little slower): there the per-record cost is dominated by
summing 512 fields, not by dispatch, so eliminating the call changes
nothing. Go is 1.08× ahead of the per-record reader — it was ~1.9×
ahead in the earlier snapshot — so what is left is a small
*compute-codegen* question (Hale's 512 field loads + adds vs Go's),
**not** a delivery-model one; `Drain<T>` fixed the delivery model,
which is all it was meant to do. The honest read: on dispatch-bound
delivery Hale is fastest; on compute-bound work over the payload it is
within about 8% of bare-loop Go.

**On ease and capability** (still true, now on top of the speed win):
**Hale** gets you typed cross-process zero-copy delivery from a single
binding line — `Tick: shm_ring("/name", slot_count: …) where
zero_copy;` — with the ring lifecycle, reader-thread polling,
release/acquire publish, and atexit `shm_unlink` all handled by the
runtime. **Go** and **Python** both reach real POSIX `/dev/shm` mmap
with stdlib only (`syscall.Mmap` / stdlib `mmap`), but you hand-roll
the file creation, `ftruncate`, slot layout, and the published
write-index the reader spins on — and they read the slot in place (Go
via `unsafe.Slice`, Python via `memoryview.cast("q")`), so their edge
was always the *bare loop* (no per-record call), which is exactly what
`Drain<T>` now matches. **Node** has *no* stdlib cross-process shared
memory at all (no mmap / POSIX shm without a native addon, which this
repo's no-extra-deps rule forbids); the rows marked † are
`worker_threads` + `SharedArrayBuffer`, shared memory between **threads
in one process**, not between processes — a strictly weaker capability
shown for honesty, so its number is *not* directly comparable.

**Is Hale's shm read genuinely zero-copy for a typed struct? Yes —
verified in the runtime.** `shm_ring_reader_thread` in
`crates/hale-codegen/runtime/lotus_shm_ring.c` calls
`handler_fn(self_ptr, slot)` where `slot` is the raw pointer returned
by `lotus_shm_ring_read_slot` (= `ring->slots_base + idx*slot_size`) —
no memcpy, no deserialize into the subscriber's arena. The codegen
side (`emit_bus_register_shm_ring` in `crates/hale-codegen/src/bus/
runtime.rs`) confirms it: unlike the in-process `lotus_bus_register`
path it passes **no** deserialize fn, and the handler signature is
identical to the in-process one — so `fn on_tick(t: Payload)` reads
`t.field` straight through the slot pointer. (This is distinct from
the regular in-process bus, which *does* serialize→deserialize a copy
into each subscriber's arena.)

**Caveat — a real Hale limitation this bench surfaced.** The large
payload was *meant* to be `type Blob { tag: Int; data: [Int; 511]; }`
(an idiomatic fixed-array field ≈ 4 KB). That **segfaults the reader
cross-process.** Hale's codegen lays out a fixed-size array field as
an *out-of-line arena pointer* inside the struct (`CodegenTy::Array`
→ `ptr` in `crates/hale-codegen/src/types/mod.rs`), so the shm slot
holds only a 16-byte `{tag, ptr}` and the pointer dangles in the
reader's address space — even though `is_flat_shapeable` in
`hale-types` *accepts* a fixed-size array as flat (so `where
zero_copy` is not rejected). The typecheck says "flat, zero-copy OK"
but the layout isn't actually inlined: a genuine flatten-the-array bug
/ optimization target. The workaround used here is a **flat struct of
512 scalar `Int` fields** (4096 bytes), which codegen *does* inline —
verified by the 4 MB shm size matching 512×8 B per slot and by the
reader's checksum matching the expected value cross-process. So the
Hale large-payload number is real and correct, but it required
side-stepping the array-field layout: today you can't carry a fixed
array inline through a zero-copy shm slot. (This caveat is orthogonal
to the delivery model — it bites the per-record and `Drain<T>` readers
alike, since both read the same slot layout.) The takeaway across both
variants: on **dispatch-bound** delivery the `Drain<T>` batch consumer
makes idiomatic Hale the fastest sibling (past Go), erasing the
bare-loop edge that per-record dispatch used to concede; on
**compute-bound** work over a large payload Hale is within about 8% of
bare-loop Go (batching doesn't address that), and the array-field
layout gap is still a concrete thing to fix before the zero-copy story
is complete.

### Refreshing the grid

This grid is a manual snapshot. Refresh it:

- **Before every Hale release.** Bench numbers are part of the
  release evidence — the grid's "Latest snapshot" version + date
  should match the tag being cut.
- **After any substantive runtime / codegen / stdlib change**
  expected to move perf.
- **After any bench-shape change** (new bench file, changed
  iter count, redesigned timed region). The new shape's
  baseline belongs in the grid AND in `baselines.json`.

Regen process:

```sh
# from this dir, with target/release/hale built upstream
./run.sh
```

Copy the per-bench `hale  elapsed_ns=...` + each sibling's
`ratio_vs_hale=...` line into the corresponding row above.
Format times in the most-readable unit (ns / µs / ms / s) and
round to 2-3 significant figures. Update the "Latest snapshot"
line:

- **Version**: matches `../hale/Cargo.toml`'s `[workspace.package]
  version`, the `hale --version` output of the binary used for
  the run, and the git tag being cut. These three should always
  agree at the moment the grid is refreshed.
- **Date**: the date the `./run.sh` was actually executed
  (results/`run-<date>.json` is the canonical artifact).
- **Hardware**: name the CPU + arch + kernel. Numbers shift
  meaningfully between machines (especially L2 size, core
  count, and SMT topology); identifying the host makes the
  grid honest about its scope.

If `./run.sh` regression-fails on a bench, either:
1. Fix the regression (preferred), or
2. Deliberately update `baselines.json` and note WHY in the
   commit message ("baseline drift after F.32-1β2 wired cache-
   padded cells; expected and documented").

Don't refresh the grid against a regressed run without
addressing the regression first — the grid is supposed to
reflect the shipped state of the language, not transient
work-in-progress.

## v1 gate measures (`gates/`)

The measures hale-lang/hale#1950 needs before v1 targets can be set:
what the toolchain costs (build time, editor latency) and what a served
program does: HTTP throughput and tail latency, memory under load, an
`@rpc` round trip, `ws::Hub` fan-out, startup, and a Postgres pool.
`gates/run.sh` takes them. **It measures only.** There are no
tolerance bands here, `run.sh` does not read them, and no number fails
the run: they are recorded so that targets can be chosen against
measurements and a later release compared with this one. Comparative
siblings are not the point; these are Hale-toolchain measures.

### Rerun

```sh
# 1. A hale checkout, built whole (the editor and build measures read
#    programs from it; std::ts needs the workspace build):
git clone https://github.com/hale-lang/hale
cd hale && cargo build --release && cd ..

# 2. This repo beside it; then, from this repo's root:
gates/run.sh                       # all of them, ~16 min; table on stderr
gates/run.sh --only=http,memory    # a subset of build,http,memory,lsp,api,hub,startup,pg
gates/run.sh --record              # also write the medians to baselines.json ("gates"),
                                   # replacing only the areas this run measured
```

`HALE_BIN` picks the binary as `run.sh` does; `HALE_SRC` names the hale
checkout to read programs from (default: the checkout `HALE_BIN` sits
in, else `../hale`). The checkout is only read; builds run on a copy.
`--reps=N` (default 5) repeats each HTTP, API and hub measure (pg runs
3), `--build-reps=N` (default 3) each build, and `--memory-seconds=N`
(default 120) sets the memory run's length. Needs jq, `/usr/bin/time`,
python3 and rustc, nothing beyond their standard libraries. `pg` also
needs docker: it starts a `postgres:16` container named
`hale-bench-pg-<pid>` on a free loopback port and removes it, volume
included, when it ends. Without docker it says so and skips. Every run writes
`results/gates-<stamp>.json` with each repeat's raw numbers.

Compare like with like: the same machine, idle, the same build profile.

### Results

hale **v0.36.0** (main 1e4fd190d), 2026-11-19, the same day's full
run as the grid. AMD Ryzen 7 9800X3D,
8 cores / 16 threads, 31 GiB, Linux 6.18, otherwise idle. The median of
the repeats (builds 3, HTTP 5), with the range across them;
`baselines.json`'s `gates` holds the same rows.

| Area | Measure | Median | Range |
|---|---|---|---|
| build | small program, cold | 5.94 s | 5.93 to 6.08 |
| build | small program, warm, unchanged | 1.81 s | 1.80 to 1.81 |
| build | small program, after a one-line edit | 1.81 s | 1.80 to 1.82 |
| build | small program, cold, peak RSS | 208 MiB | 208 to 208 |
| build | `dna/host`, cold | 20.72 s | 20.72 to 20.85 |
| build | `dna/host`, warm, unchanged | 15.85 s | 15.79 to 15.91 |
| build | `dna/host`, after a one-line edit | 15.83 s | 15.80 to 15.87 |
| build | `dna/host`, cold, peak RSS | 1051 MiB | 1051 to 1051 |
| http | 1 connection: requests/s | 46,630 | 46,532 to 46,952 |
| http | 1 connection: p50 / p99 | 20 / 28 µs | p99 27 to 28 |
| http | 16 connections: requests/s | 81,620 | 80,976 to 81,764 |
| http | 16 connections: p50 / p99 | 193 / 240 µs | p99 238 to 246 |
| http | 64 connections: requests/s | 81,585 | 80,558 to 82,798 |
| http | 64 connections: p50 / p99 | 774 / 870 µs | p99 837 to 890 |
| http | errors / dropped attempts, every run | 0 / 0 | |
| memory | server RSS: idle, at 10 s, at 120 s of load | 4.7, 4.7, 4.7 MiB | |
| memory | RSS growth from 10 s to 120 s (9.8 M requests, 0 errors, 0 dropped) | 0.0 KiB/min (flat) | |
| editor | small seed: open, to diagnostics | 88 ms | |
| editor | small seed: edit, to diagnostics, p50 / p95 | 97 / 100 ms | 20 edits |
| editor | small seed: server peak RSS | 89 MiB | |
| editor | large seed (`dna/core`): open, to diagnostics | 733 ms | |
| editor | large seed: edit, to diagnostics, p50 / p95 | 749 / 759 ms | 20 edits |
| editor | large seed: server peak RSS | 303 MiB | |
| api | unix rpc, 1 connection: calls/s | 55,303 | 55,091 to 55,547 |
| api | unix rpc, 1 connection: p50 / p99 | 17 / 21 µs | p99 21 to 23 |
| api | unix rpc, 16 connections: calls/s | 148,449 | 145,518 to 149,469 |
| api | unix rpc, 16 connections: p50 / p99 | 103 / 146 µs | p99 145 to 147 |
| api | errors / dropped calls, every run | 0 / 0 | |
| hub | burst of 10,000 to 1 / 16 / 64 clients: deliveries/s | 245,212 / 206,353 / 188,956 | |
| hub | burst: dropped deliveries / refused upgrades, every run | 0 / 0 | |
| hub | paced (1 ms apart), 1 client: delivery p50 / p99 | 12 / 22 µs | p99 17 to 35 |
| hub | paced, 64 clients: delivery p50 / p99 | 204 / 393 µs | p99 387 to 394 |
| startup | `http_serve`: spawn to first answered request | 598 µs | 583 to 790 |
| startup | binary size: `http_serve` / `rpc_serve` / `hub_serve` | 1.60 / 1.68 / 1.69 MiB | |
| pg | `SELECT 1` | 19.7 µs | 19.4 to 21.9 |
| pg | primary-key lookup, 1,000 rows | 22.6 µs | 22.5 to 23.1 |
| pg | one-INSERT transaction, commit flushed | 1.94 ms | 1.87 to 2.02 |
| pg | one-INSERT transaction, `synchronous_commit` off | 65.4 µs | 64.0 to 65.7 |

### What each measures

**Build** (`hale build <target> -o <tmp>`, wall time; peak RSS of the
`hale build` process from `/usr/bin/time`). The small program is
hale's `crates/hale-codegen/tests/fixtures/examples/92-build-an-api`
(an API with a surface, a handler and records); the large one is
`dna/host`, the largest program in the hale tree (the host with the
DNA core and the API it imports). *Cold* runs with an empty
`XDG_CACHE_HOME`, so the runtime's C objects are compiled and cached;
*warm* is the same build again; *after a one-line edit* appends a
comment to the target's `main.hl` first. `hale build` has no
incremental compilation beyond that runtime-object cache, so an
unchanged rebuild costs what a rebuild after an edit does, and the
cold build's extra is the cache (about 4 s small, 5 s large). Builds
use `hale build`'s defaults (release profile, host CPU).

**HTTP** (`gates/http_serve.hl` under `gates/httpload.rs`). The hale
book's minimal `std::http::Server`: a handler that counts its hits and
answers a short text body. The load generator is closed-loop: each
connection sends `GET /` as soon as the last response is in, for 10 s
after 2 s of warm-up, at 1, 16 and 64 connections. The server answers
each request with `Connection: close`, so every request includes a TCP
connect, and latency runs from the request's send to the end of its
response, reconnect included. A non-200 response is an *error*; a
connection that fails before its response is complete is a *dropped*
attempt, counted when it fails inside the window and sent again, so a
server that loses requests cannot read as error-free. The server is
one handler loop, so throughput levels off near 81,000 requests/s from
16 connections up and more connections only queue (p50 rises in
proportion).

**Memory** (the same server under load). 16 connections of constant
load for 120 s, the server's RSS (`/proc/<pid>/status` VmRSS) read
every second; growth is the least-squares slope from 10 s to the end.

**Editor** (`gates/lsp_latency.py`). A client drives `hale lsp` over
stdio: it opens one file and times the diagnostics that follow, then
makes 20 edits (a comment line added at the end of the file, then
removed, alternately; full-document sync). Each time runs from the
client's write to the last `publishDiagnostics` of the pass, the
server then silent for 1 s. The small seed is
`92-build-an-api/main.hl`; the large seed is `dna/core`, opened at
`assembly.hl`, which the server checks whole on every event. Peak RSS
is the server's VmHWM at the end.

**API** (`gates/rpc_serve.hl` under `gates/rpcload.rs`). One `@rpc`
method (`Echo::on_ping`) is served with `api::serve` over `unix::Rpc`,
its receiver on an async_io pool. main parks on the exposure's `wait()`:
a serving `run()` that sleeps in a loop answers each call only when its
sleep slice ends, about 100–250 ms a call (hale-lang/hale#2091). The
client is closed-loop: each connection sends the next JSON-line call
when the last reply is read, for 10 s after 2 s of warm-up, at 1 and 16
connections. A reply without `"ok":true` is an error, and a call whose
connection fails is dropped and counted.

**Hub** (`gates/hub_serve.hl` under `gates/wsload.rs`). A `ws::Hub`
streams the topic `Ticks` (`bound: 4096, on_full: drop_old`) to N
websocket clients that each subscribe and wait for `subscribed`.
- *Burst:* 10,000 ticks are published back to back, timed from the
  command to the last delivery. Expected minus received is the
  dropped count (`drop_old` sheds under a slow reader).
- *Paced:* 500 ticks, 1 ms apart, each reaching an idle hub. Every
  tick carries its publish time on the host's monotonic clock, so a
  delivery's latency is read against the same clock.

**Startup** (`gates/httpload.rs --startup`). This spawns `http_serve`
on a free port and polls `GET /health` every 100 µs, timing from the
spawn to the first `200`. Sizes are the three servers' binaries as
`hale build` makes them (release, host CPU, not stripped).

**Postgres** (`gates/pq_bench.hl`). This uses `pq`, the pure-Hale
Postgres client (the hale tree's `dna/core/pond/pq`; no libpq), on a
`PgPool` of two connections, against `postgres:16` in a throwaway
container on the loopback. Every operation runs sequentially: 20,000
`SELECT 1`s, 20,000 primary-key lookups, and 5,000 transactions around
one INSERT. The transactions run twice: with the server's default
flushed commit, which this machine's disk dominates, and with
`synchronous_commit` off, which leaves the client and server path
(three round trips).

Not measured here: cross-machine bus transports and HTTPS. Each needs
a harness of its own.

## Three kinds of microbench

The benches under `micro/` split into **three categories**
answering different questions. Mix them with care — they're not
interchangeable.

### Overhead microbenches — "what does the substrate cost when unused?"

Strip allocation work down to nothing so the substrate machinery
runs alone. These deliberately measure Hale's worst case: the
arena lifecycle gets no chance to amortize against work it would
normally accompany.

- **`loop_overhead`** — tight `acc ^= i` reduction over 100M iters
  (pid-seeded + printed so it can't fold to a constant). Under the
  native-CPU + O3 defaults LLVM autovectorized it to AVX-512 (~10× vs
  Go's scalar loop through v0.32.7). Since hale#1874 the loop, being in
  `fn main`, carries the drain latch on its back-edge, which keeps it
  scalar: it now measures the scalar loop plus that latch, at parity
  with Go ([hale#2089](https://github.com/hale-lang/hale/issues/2089)).
  No arena work.
- **`fn_call`** — `fn step(x) -> Int { return x * 2 + 1; }` called
  10M times: free-fn call overhead for a minimal *real* body. A free
  fn that allocates nothing skips its per-call scratch arena
  (`//go:noinline` on the Go sibling keeps it a fair real-call
  comparison). Before the 2026-06-28 allocation-classification work
  this body's `+` was treated as possibly-String-concat, so the call
  paid a scratch malloc/free (~10 ns/call); the type-aware `Add`
  classification recognizes `Int + Int` as arithmetic and now it runs
  at ~1 ns. (The earlier `return x;` body measured nothing — a bare
  identifier was always elided.)
- **`fn_modular`** — `outer(x) { return inner(x) * 3; }` over
  `inner(x) { return x + 1; }`, 10M times: the "is factoring a hot
  path into composed helpers free?" bench. Before the interprocedural
  non-allocating propagation (2026-06-28), *calling any function*
  marked the caller possibly-allocating, so `outer` paid a scratch
  malloc per call even though `inner` allocates nothing (~21 ns/call);
  the call-graph fixpoint now proves the whole chain non-allocating
  and it runs at ~2 ns. On factored code Hale went from ~13× Go's
  (no-inline) call overhead to ~2.5× at the time, and to ~1.15× as of
  the 2026-10-28 grid.
- **`locus_instantiation`** — `Empty {}` 100k times,
  statement-position. Arena create + struct init + arena destroy
  with zero allocations in between.
- **`bus_dispatch`** — 100k typed messages through the bus (N
  matched across all language variants; raised from 10k for
  lower run-to-run variance). The per-message payload memcpy +
  queue enqueue is the design (per
  `memory.md` "pointers don't cross loci; values do") but the
  bench measures it isolated.
- **`bus_round_trip`** — 200k request/reply round trips, one in
  flight: main publishes a Ping, an Echo locus on main's pool answers
  with a Pong, main yields until it is in, then sends the next.
  `bus_dispatch` measures throughput (the queue never empties); this
  is the latency a request/reply caller waits. Hale-only: a Go
  channel ping-pong would measure the goroutine scheduler instead.
- **`json_encode`** — 200k `Quote::to_json` encodes of
  `json_parse`'s record (`seq` varies per iteration so nothing
  hoists); the output lengths are folded and printed. Siblings:
  Go `json.Marshal`, `JSON.stringify`, `json.dumps` (compact).
- **`form_vec_push`** — 500k pushes only. Isolated growth path.
- **`form_vec_get`** — 200k indexed reads only. Isolated read
  path.
- **`form_hashmap_set`** — 1M Int-keyed inserts into a
  `@form(hashmap)` locus. Tests hash + slot probe + entry
  memcpy + occasional grow/rehash.
- **`form_hashmap_get`** — 150k Int-keyed lookups against a
  pre-populated `@form(hashmap)`. Cliffs at n=200k (set+get
  doubles per-iter work vs pure-write set).

These benches surface codegen overhead the compiler team can
target (e.g. eliding arena subregions when a fn provably doesn't
allocate). Some still show overhead (`fn_call`,
`locus_instantiation`), but the `@form` collection benches now
**lead** Go: after the `.get`/`.push`/`.set`/`.pop` inlines, the
counted-loop bounds-check elimination (`for j in 0..v.len()`
drops the per-read check Go still pays), and the native
target-cpu + O3 defaults, `form_vec_push` is ~3.5× *faster* than Go,
and `form_vec_get` was ~3.1× faster through v0.32.7 (at parity since
hale#1874's drain latch keeps its read loop in `fn main` scalar;
hale#2089). (An earlier note here
claimed `form_vec_get` was "60× behind Go" — that was a
benchmark bug: the Hale variant ran 25× more iterations than the
`.go`/`.js`/`.py` variants, so the ratio compared different
workloads. The N is now matched, comfortably inside
`spec/forms.md` FORM-3's "within 10% of C" target.)

### Amortized microbenches — "does the design pay off when used as intended?"

Match the shape the design optimizes for: many allocations
inside one arena, wholesale-free at dissolve. The substrate cost
is paid once across N units of work, not per unit.

- **`vec_amortized`** — push N + fold N, single timed region.
- **`fn_scratch_work`** — 100 fn calls × 1000-element local
  `@form(vec)` per call. The m49 subregion gets a real workout.
- **`coord_with_churn`** — chunked-class parent accepting K=2000
  Worker children (N matched across all language variants; the
  old k≈25 accept() accumulation cliff was lifted in the
  cliff-lift session). Tests F.3 free-list reclamation + chunked
  sub-region allocator.

These are where Hale's region model is supposed to win. The
ratio against Go is the right signal — if amortized benches show
Hale competitive with Go and overhead benches don't, the
design is real but the compiler is leaving per-op cost on the
table.

### Coordinated-workload microbenches — "does the design win in multi-locus shapes?"

The shape Hale is *built for*: multiple loci deep, lateral
siblings, coordinating via vertical-only flow or bus. The design
predicts these should out-throughput dynamic-language alternatives
because region memory + cooperative scheduling + bus-mediated
typed messages avoid the per-allocation GC tracking those
languages pay.

- **`tree_fanout`** — depth=2 with K=20 lateral siblings.
  Coordinator's accept() calls `worker.compute()` for each
  child; results aggregate into parent state. Tests hierarchical
  region memory + cross-locus method dispatch. **First bench
  where Hale decisively beats Node (9.9×) and Python (24×).**
- **`pipeline_3stage`** — depth=3 sequential. Source → Filter →
  Sink via two bus subjects. Tests multi-stage bus coordination
  + the cooperative scheduler's drain semantics. Currently
  bottlenecked by per-event bus-dispatch overhead — same shape
  that limits `bus_dispatch`.

### Cross-pool / cache microbenches — "does the substrate respect the cache hierarchy?"

The F.32 cache-aware substrate work (`notes/f32-cache-aware-delivery-plan.md`
in the hale repo) added a new bench family in 2026-05-24 covering
cross-pool dispatch + concurrent `@form(hashmap)` access. These
benches gate the F.32 deliverables — each shipped F.32-N piece
either lands or is rejected against a baseline here.

- **`bus_dispatch_cross_pool`** — same shape as `bus_dispatch`,
  but the subscriber runs on the `io` cooperative pool (a
  separate OS thread). Measures publisher-side enqueue cost
  for the cross-thread mailbox path. Pairs with the prefetch
  hint shipped in F.32-4-prefetch (`__builtin_prefetch` in
  `lotus_coop_pool_post`).
- **`bus_round_trip_cross_pool`** — `bus_round_trip` with the Echo
  locus on the `io` pool: 100k round trips, each two cross-thread
  posts and their wake-ups (about 1.5 µs). The latency counterpart of
  `bus_dispatch_cross_pool`'s throughput. Hale-only.
- **`form_hashmap_false_sharing`** — two pools concurrently
  write disjoint keys (even / odd ids) into a shared
  `@form(hashmap, sync = serialized)`. The Prometheus-counter
  shape that drove F.32-0 + F.32-1α. Today's baseline uses
  `sync = serialized` (per-map mutex); when F.32-1β2 ships
  the annotation flips to `sync = striped` for parallel
  writers + cache-padded cells.
- **`form_hashmap_walk_large`** — pre-populate ~100k entries
  then iterate via `key_at` / `entry_at`. TLB-bound at scale;
  used to detect regressions in arena chunk allocation and
  to measure the win from F.32-4a (huge pages, opt-in via
  `LOTUS_HUGE_PAGES=1`).

The cross-pool benches' Go siblings use `runtime.LockOSThread`
to pin goroutines to distinct OS threads — the closest
analogue of "cooperative pool owns its own thread." JS and
Python siblings approximate via `worker_threads` and
`threading.Thread` respectively; both pay overhead that
Hale doesn't (V8 structured-clone, CPython GIL), so the
ratio columns for these benches are informational only,
not strict apples-to-apples.

### App benches — `app/`

- **`stream_aggregator`** — publisher fires N typed events; a
  long-lived aggregator subscribes and maintains running stats.
  Cross between bus_dispatch and a real workload.

### Reclamation microbenches — "is what a write replaces given back?"

A long-lived locus rewrites the same fields and collections forever;
each bench here churns one of those shapes 1M times in a method, and
holds its arena flat only if the replaced value is retired and
reused. They are Hale-only: what they measure is Hale's reclamation,
which a GC'd sibling does not have. A leak shows as memory AND time —
the containment walk crosses every leaked chunk — so a reclamation
regression trips the time band too. Pre-fix numbers are in each
file's header.

- **`field_same_len`** — a String self field rewritten at the same
  length: the in-place path (hale-lang/hale#1033 kept it).
- **`field_alt_empty`**, **`field_alt_short`** — a String self field
  alternating heap / empty and 5 / 2 bytes (hale#1033).
- **`field_bytes_alt`** — the Bytes side of the same (hale#1033).
- **`field_whole_struct`** — `self.f = Frame { .. }` replaced whole,
  String and Bytes fields retired (hale#1033).
- **`vec_queue_pop`** — a `@form(vec)` used as a queue, push then
  pop, the element carrying a String and a Bytes (hale#1037).
- **`vec_set_bytes`** — `@form(vec).set` over a struct carrying
  Bytes (hale#1037).

### Per-iteration reclaim microbenches — "does a long loop stay flat?"

A loop in a locus method, a lifecycle hook or a handler used to put
every iteration's values in the frame's per-call scratch, freed only
when the frame returned. Since hale-lang/hale#1765 a loop body the
reclaim rule admits gets an arena of its own for each iteration
(`lotus_arena_iteration_enter` at the body's entry), so what an
iteration makes is freed when the next one starts.

- **`method_loop_alloc`** — a locus method loops 10M times, each
  iteration formatting the counter into a fresh String
  (`to_string(i)`) and reading its length. Nothing outlives the
  iteration. maxrss stays at about 5 MB; before #1765 the same loop
  peaked at about 317 MB. A regression in time or maxrss here means
  the loop stopped reclaiming per iteration. Go, Node and Python
  siblings run the same loop in a method on a struct or class.

### Text, bounded-list and ring microbenches

Each file's header has the details.

- **`str_words`**, **`str_words_chain`**: `std::str::words` over a
  10 KB text as a `for` source, and the same count as a chain.
- **`str_csv_sum`**: `std::str::lines` as a `for` source and
  `std::str::split(..).map(parse_int).sum()` per row.
- **`str_concat_loop`**: `s = s + "ab"` 1M times (linear building,
  hale-lang/hale#1960).
- **`str_match`**: a string `match` against 16 literal arms.
- **`display_template`**, **`display_fstring`**: a record rendered
  through its `@display` template, and through the f-string the template
  stands for. Both are Hale-only.
- **`bounded_records`**: `bounded[T; N]` push, `at`/`set` and the
  hale-lang/hale#2067 summary push, on records holding Strings. It runs
  in a locus method; see hale-lang/hale#2090 for why.
- **`ring_buffer_steady`**: a `@form(ring_buffer)` of records in steady
  state; maxrss is the flat-memory check (hale-lang/hale#2044).
- **`bounded_kernel_int`**, **`_u32`**, **`_u16`**: one reduction (refill
  a `bounded[T; 4096]` record field, fold `x * 3` over it) at three
  element widths, the fixed-width integers' point (hale-lang/hale#2132):
  a `U32` or `U16` buffer is a half or a quarter of an `Int`'s, and its
  `wrapping_*` fold is plain `i32` arithmetic the vectorizer widens to
  four lanes a NEON instruction, where aarch64 has no `i64` vector
  multiply. Hale-only: the comparison is between the widths.

C siblings exist where the shape translates (`str_*` scans, a doubling
buffer, an `strcmp` chain, a fixed ring). `bounded_records` has none,
because an honest one would need its own string ownership scheme.

## Layout

```
.
├── README.md                this file
├── run.sh                   shell + jq harness
├── baselines.json           checked-in Hale medians + tolerance bands
├── results/                 per-run JSON reports (gitignored)
├── micro/
│   │
│   │   # Overhead microbenches (isolate substrate cost)
│   ├── loop_overhead.{ap,go,js,py}
│   ├── fn_call.{ap,go,js,py}
│   ├── fn_modular.{ap,go,js,py}
│   ├── locus_instantiation.{ap,go,js,py}
│   ├── bus_dispatch.{ap,go,js,py}
│   ├── form_vec_push.{ap,go,js,py}
│   ├── form_vec_get.{ap,go,js,py}
│   ├── form_hashmap_set.{ap,go,js,py}
│   ├── form_hashmap_get.{ap,go,js,py}
│   ├── json_parse.{hl,c,rs,go,js,py}, json_encode.{hl,go,js,py}
│   │
│   │   # Amortized microbenches (match design's optimization target)
│   ├── vec_amortized.{ap,go,js,py}
│   ├── fn_scratch_work.{ap,go,js,py}
│   ├── coord_with_churn.{ap,go,js,py}
│   │
│   │   # Coordinated-workload microbenches (multi-locus shapes)
│   ├── tree_fanout.{ap,go,js,py}
│   ├── pipeline_3stage.{ap,go,js,py}
│   │
│   │   # Cross-pool / cache microbenches (F.32)
│   ├── bus_dispatch_cross_pool.{hl,go,js,py}
│   ├── bus_round_trip.hl, bus_round_trip_cross_pool.hl
│   ├── form_hashmap_false_sharing.{hl,go,js,py}
│   ├── form_hashmap_walk_large.{hl,go,js,py}
│   │
│   │   # Reclamation microbenches (Hale-only)
│   ├── field_same_len.hl, field_alt_empty.hl, field_alt_short.hl
│   ├── field_bytes_alt.hl, field_whole_struct.hl
│   ├── vec_queue_pop.hl, vec_set_bytes.hl
│   │
│   │   # Per-iteration reclaim microbenches
│   ├── method_loop_alloc.{hl,go,js,py}
│   │
│   │   # Text, bounded-list and ring microbenches
│   ├── str_words, str_csv_sum, str_concat_loop, str_match .{hl,c,rs,go,js,py}
│   ├── str_words_chain.hl, display_template.hl, display_fstring.hl
│   ├── bounded_records.{hl,rs,go,js,py}
│   ├── bounded_kernel_int.hl, bounded_kernel_u32.hl, bounded_kernel_u16.hl
│   └── ring_buffer_steady.{hl,c,rs,go,js,py}
├── app/
│   └── stream_aggregator.{ap,go,js,py}
├── gates/                   v1 gate measures (own runner; measures only)
│   ├── run.sh               build, http, memory, lsp
│   ├── http_serve.hl        the served program
│   ├── httpload.rs          closed-loop HTTP/1.1 load generator (std only)
│   ├── lsp_latency.py       an LSP client that times `hale lsp`
│   ├── rpc_serve.hl         one @rpc method over unix::Rpc
│   ├── rpcload.rs           closed-loop JSON-line RPC client (std only)
│   ├── hub_serve.hl         a ws::Hub streaming one topic
│   ├── wsload.rs            N websocket clients, fan-out and latency (std only)
│   └── pq_bench.hl          the pure-Hale pq client on a pool
└── c-twins/                 (placeholder) hand-written C equivalents
                             for FORM-3 10%-gate comparisons.
```

## Conventions

Every bench (any language) self-times the work-of-interest with
a monotonic clock and prints exactly one `elapsed_ns=N` line on
stdout. The harness additionally captures `maxrss_kb` externally
via `/usr/bin/time -v`. The runner takes N samples per bench
(default 5), records the median, and writes both per-sample
arrays and the median into the JSON report.

**Monotonic clocks used:**
- Hale: `std::time::monotonic()` → Duration ns
- Go: `time.Since(t0).Nanoseconds()`
- Node: `process.hrtime.bigint()`
- Python: `time.monotonic_ns()`

**Regression gate (Hale only).** A bench fails when:

```
current_median > baseline_elapsed_ns * (1 + tolerance)
```

Faster-than-baseline is never a regression. The default tolerance
is **0.30** — sub-10ms benches routinely jitter ±20% under OS
noise. Tighten per-bench in `baselines.json` once a metric
stabilizes. Comparative numbers (go/node/python) are emitted in
the report but **never** trigger exit 1.

**Toolchain detection.** The harness checks for `go`, `node`,
and `python3` on PATH at startup. Each comparative language is
silently skipped if its toolchain is missing.

## Adding a bench

1. Decide which category: overhead microbench (isolate a primitive
   under worst-case conditions), amortized microbench (real
   workload shape), or app bench (mixed-workload end-to-end).
2. Drop a `.hl` file in `micro/` or `app/`. Each one
   must:
   - Self-time the work-of-interest with two `std::time::monotonic`
     calls and `t1 - t0` arithmetic.
   - Print `elapsed_ns=` followed by the duration value on its
     own line.
3. Add sibling `.go`, `.js`, `.py` files implementing the same
   shape as closely as the language permits. Each must also
   print one `elapsed_ns=N` line. The harness picks them up
   automatically by filename stem.
4. Run `./rebaseline.sh` to seed (`run.sh --update-baselines`
   is retired; see **Tolerance bands**).
5. Commit the new sources + the updated `baselines.json`.

## Reading the report

```json
{
  "generated_at": "...",
  "iters": 5,
  "benches": [
    {
      "name": "fn_scratch_work",
      "kind": "micro",
      "status": "ok",
      "elapsed_ns_median": 469208,
      "elapsed_ns_samples": [...],
      "maxrss_kb_median": 3088,
      "maxrss_kb_samples": [...],
      "baseline_elapsed_ns": 469208,
      "baseline_maxrss_kb": 3088,
      "note": null,
      "comparatives": {
        "go":     { "elapsed_ns_median": 397163,  "ratio_vs_hale": 0.8465, ... },
        "node":   { "elapsed_ns_median": 918277,  "ratio_vs_hale": 1.9571, ... },
        "python": { "elapsed_ns_median": 2578210, "ratio_vs_hale": 5.4948, ... }
      }
    }
  ]
}
```

`ratio_vs_hale = lang_elapsed / hale_elapsed`. A value of
**0.5** means the other language is 2× faster than Hale; **2.0**
means Hale is 2× faster than the other language; **1.0** is
parity.

## Known constraint — accumulation ceiling (LIFTED 2026-07-01)

**Historical.** Several Hale substrate paths used to segfault
under v1 codegen between 100k and 1M iterations of a tight
loop — root cause was a statement-position locus lowering to a
dynamic stack alloc per iteration (blew the 8 MB stack at
~500k), fixed by the entry-block alloca hoist; the separate
`accept()`-in-a-loop cliff at k≈25 fell in the 2026-05-16
cliff-lift session. A 2026-07-01 sweep re-stressed every
substrate shape on hale v0.9.2+: vec push+get to 100M, hashmap
set+get to 20M, bus dispatch to 10M, cross-pool dispatch to
10M, 3-stage pipeline to 5M, heap-payload dispatch to 10M,
locus instantiation to 10M, accept-fanout to K=2M, and
accept-churn to K=4M — **all clean**. Iteration counts in the
`.hl` files are now set for cross-language workload parity, not
to dodge a ceiling.

The sweep did find (and fix, hale 2026-07-01) one real residual:
under interest-based ownership (v0.9.2) an accept'd child's
locus STRUCT was bump-allocated in the owner's arena and never
recycled, so churn daemons grew ~sizeof(child struct) per child
forever — OOM-shaped, not segfault-shaped. The child-struct
free-list now restores F.3's O(peak-alive) contract for flow
children (measured: flat 5.5 MB at K=4M, was 443 MB). Note the
semantics: a child is only reclaimed mid-life if its parent
declares `release(c: Child)` (flow) or it `terminate;`s —
without one of those an accept'd child is a RESIDENT and
accumulates by design until the parent dissolves
(`coord_with_churn` declares `release` for exactly this
reason).

## Rust + C comparators (2026-07-01)

Every micro/app bench now has `.c` and `.rs` siblings — the title
comparison the suite existed to make. Build posture is
toolchain-fair: `clang -O3 -march=native` and `rustc -O
-C target-cpu=native` against Hale's default O3 + host tuning.
The ports mirror the `.go` siblings' workload shapes exactly
(same counts, same timed regions, `__attribute__((noinline))` /
`#[inline(never)]` where the Go used `//go:noinline`); headers
document per-file caveats.

Second run (2026-07-02 PM, same host, after the fn-call protocol
shave, the @form iteration surface, and dead-stdlib DCE landed —
fn_call 0.40 → 0.80, fn_modular 0.40 → 0.88, walk_large 0.07 →
0.30 vs Rust and 1.92× vs C). Median of 5. Ratio = lang/hale;
**> 1 means Hale is faster**:

| bench | hale ns | c/hale | rust/hale |
|---|---|---|---|
| form_hashmap_walk_large | 301,093 | **1.92** | 0.30 |
| bus_dispatch | 173,334 | **1.88** | **4.53** |
| bus_dispatch_cross_pool | 4,963,635 | **1.26** | 0.72 |
| form_hashmap_set | 43,291,062 | **1.40** | 0.82 |
| form_hashmap_false_sharing | 16,953,313 | **1.34** | 0.91 |
| form_hashmap_get | 1,023,635 | **1.07** | **1.23** |
| form_vec_get | 11,281 | **1.04** | 0.97 |
| form_vec_push | 680,112 | 0.93 | 0.97 |
| stream_aggregator | 408,334 | 0.94 | 0.95 |
| vec_amortized | 332,782 | 0.81 | 0.82 |
| loop_overhead | 1,818,352 | 0.90 | **1.12** |
| fn_modular | 17,654,675 | 0.88 | 0.87 |
| fn_call | 9,587,696 | 0.80 | 0.80 |
| fn_scratch_work | 55,644 | 0.74 | 0.80 |
| coord_with_churn | 28,794 | 0.49 | 0.39 |
| locus_instantiation | 1,322,073 | 0.35 | 0.52 |
| bus_dispatch_heap_payload | 1,510,496 | 0.32 | 0.74 |
| json_parse | 61,047,909 | 0.10 | 0.39 |
| pipeline_3stage | 1,758,139 | 0.08 | 0.16 |
| tree_fanout | — | n/c | n/c |
| form_chunk_hint_multi_locus | — | n/c | n/c |

Reading it honestly:

- **Hale's substrate WINS against hand-written C** where the
  design bet lives: subject-keyed dispatch (static-devirt bus vs
  C's FNV-router + indirect call, 1.9×; vs Rust's boxed-closure
  HashMap dispatch, 5.2×), hashmap writes (1.34× vs a hand-rolled
  open-addressing C table), cross-thread posting (1.39× vs a
  mutex+condvar ring), contended writes (1.30×).
- **Parity band** (±15%): loops, vec reads/amortized cycle,
  hashmap reads, the stream-aggregator app shape.
- **The losses are the known per-op overheads**, now measured
  against the real target: free-fn calls 2.5× behind (all three
  compiled comparators agree at ~7.7 ms — the gap is Hale's
  call protocol, not codegen), locus instantiation 2–3×,
  accept-churn ~3×, pipeline hops 6–11× (C/Rust make direct
  synchronous calls; Hale pays queue + payload-copy semantics —
  extending static devirtualization across the hop chain is the
  fix), hashmap ITERATION 13× behind Rust (`key_at`/`entry_at`
  per-slot calls vs a native iterator — the deferred
  `@form(hashmap)` iteration surface is the fix), and
  schema-specialized parsing (C's hand-rolled extractor 10×).
- **Non-comparable rows:** `tree_fanout` (LLVM folds the
  triangular sum to closed form in the C/Rust ports) and
  `form_chunk_hint_multi_locus` (the .hl/.rs elapsed includes a
  200 ms drain sleep; the .c doesn't — coverage bench, not a
  ratio signal).

## Future work

- **Erlang (BEAM)** is the natural next comparator since Hale's
  runtime model is BEAM-shaped.
- **`hale bench` CLI.** Per `spec/testing.md`, this surface is
  planned but not shipped. The shell harness here is the current
  stand-in.
- **xproc C/Rust twins** for the cross-process SHM path (the
  in-process suite above doesn't cover it).
