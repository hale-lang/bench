# Hale benchmark suite

Performance harness for Hale, comparing against Go / Node / Python
sibling implementations of the same workload shape. For the language
itself, see [hale-lang/hale](https://github.com/hale-lang/hale).
Baseline scaffold for Layer 3 (performance) per `spec/testing.md` in
the hale repo.
Microbenches isolate substrate primitives; one app-level bench
exercises a small mixed workload end-to-end. The runner is
shell + jq, no extra build dependencies.

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
./run.sh --update-baselines    # overwrite baselines.json with new Hale medians
./run.sh --no-build            # skip rebuild step
./run.sh --no-comparative      # Hale only, skip go/node/python siblings
./run.sh --json                # emit only the JSON report to stdout
```

Each invocation writes a timestamped JSON report under
`results/` (gitignored).

## Cross-language comparative grid

Latest snapshot: **Hale v0.8.3** (2026-06-25), AMD Ryzen 7
9800X3D / x86_64 / Linux 6.18.

Read each cell as `<elapsed> (<ratio_vs_hale>×)` where
**ratio = sibling_time / hale_time**:

- ratio > 1 → sibling is **slower** than Hale by that factor.
- ratio < 1 → sibling is **faster** than Hale by 1/ratio.
- `—` → no sibling exists for this bench (Hale-only).

### Overhead microbenches

| Bench | Hale | Go | Node | Python |
|---|---:|---:|---:|---:|
| `loop_overhead`             | 11.57 ms | 19.21 ms (1.66×) | 20.33 ms (1.76×) | 3.36 s (290×) |
| `fn_call`                   | 19.14 ms | 7.72 ms (0.403×) | 4.41 ms (0.230×) | 517.65 ms (27.0×) |
| `fn_modular`                | 38.65 ms | 15.41 ms (0.399×) | 4.04 ms (0.105×) | 630.74 ms (16.3×) |
| `locus_instantiation`       | 1.25 ms | 152.66 µs (0.122×) | 1.02 ms (0.816×) | 12.67 ms (10.1×) |
| `bus_dispatch`              | 1.79 ms | 46.21 µs (0.0258×) | 308.33 µs (0.172×) | 1.09 ms (0.609×) |
| `bus_dispatch_heap_payload` | 1.51 ms | — | — | — |
| `bus_publish_shm_ring`      | 1.34 ms | — | — | — |
| `form_vec_push`             | 572.86 µs | 2.76 ms (4.83×) | 3.43 ms (5.99×) | 13.31 ms (23.2×) |
| `form_vec_get`              | 14.94 µs | 38.84 µs (2.60×) | 672.27 µs (45.0×) | 8.17 ms (547×) |
| `form_hashmap_set`          | 43.24 ms | 47.80 ms (1.11×) | 81.57 ms (1.89×) | 262.14 ms (6.06×) |
| `form_hashmap_get`          | 5.23 ms | 1.09 ms (0.208×) | 2.47 ms (0.473×) | 10.51 ms (2.01×) |
| `json_parse`                | 57.97 ms | 150.02 ms (2.59×) | 51.04 ms (0.88×) | 213.97 ms (3.69×) |

`json_parse` is 200k parses of a 7-field market-data quote
via the inlined `Type::from_json`. Hale **beats Go's
encoding/json 2.59× and Python's json.loads 3.69×**, and
sits ~12% behind V8's `JSON.parse` (0.88×) — the closest a
non-V8 contender gets here, after the inline-parser +
string-fast-path + leaf-primitive inlining work.

### Amortized microbenches

| Bench | Hale | Go | Node | Python |
|---|---:|---:|---:|---:|
| `vec_amortized`     | 959.28 µs | 1.25 ms (1.3×) | 2.93 ms (3.05×) | 13.23 ms (13.8×) |
| `fn_scratch_work`   | 420.75 µs | 449.95 µs (1.07×) | 952.79 µs (2.26×) | 2.61 ms (6.2×) |
| `coord_with_churn`  | 42.96 µs | 0.16 µs (0.0037×) | 32.18 µs (0.749×) | 4.06 µs (0.0944×) |

### Coordinated-workload microbenches

| Bench | Hale | Go | Node | Python |
|---|---:|---:|---:|---:|
| `tree_fanout`      | 19.50 µs | 8.01 µs (0.411×) | 242.45 µs (12.4×) | 575.17 µs (29.5×) |
| `pipeline_3stage`  | 3.89 ms | 214.93 µs (0.0552×) | 1.10 ms (0.281×) | 6.98 ms (1.79×) |

### Cross-pool / cache microbenches (F.32)

| Bench | Hale | Go | Node | Python |
|---|---:|---:|---:|---:|
| `bus_dispatch_cross_pool`     | 10.72 ms | 7.72 ms (0.720×) | 39.83 ms (3.72×) | 82.32 ms (7.68×) |
| `form_hashmap_false_sharing`  | 15.91 ms | 9.95 ms (0.625×) | 84.88 ms (5.34×) | 36.20 ms (2.28×) |
| `form_hashmap_walk_large`     | 1.20 ms | 381.18 µs (0.317×) | 729.95 µs (0.608×) | 7.62 ms (6.35×) |

`form_hashmap_false_sharing` exercises the F.32-1γ-v2
`sync = lockfree` discipline (cell-level CAS on the
steady-state hot path; `remove` via tombstones; transparent
grow when load factor exceeds 0.6). On this 2-core /
cheap-payload bench, lockfree closes the gap with Go's
sync.Mutex map from 1.66× (under α serialized) to 1.18×.
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
lock), within its widened 0.40 tolerance and documented in
`baselines.json`.

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

### App benches

| Bench | Hale | Go | Node | Python |
|---|---:|---:|---:|---:|
| `stream_aggregator`  | 5.26 ms | 229.21 µs (0.0436×) | 1.71 ms (0.326×) | 30.85 ms (5.87×) |

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

Snapshots (AMD Ryzen 7 9800X3D / x86_64 / Linux 6.18, median of 20
runs):

**small — N = 200 000, 16-byte records**

| language | median | ratio_vs_hale |
|---|---:|---:|
| **Hale** — per-record handler | 10.80 ms | 1.00× |
| **Hale** — `Drain<T>` batch | **2.29 ms** | **0.21×** |
| Go | 2.61 ms | 0.24× |
| Node | 10.30 ms | 0.95× † |
| Python | 31.28 ms | 2.90× |

**large — N = 20 000, ~4 KB records (reader sums whole payload)**

| language | median | ratio_vs_hale |
|---|---:|---:|
| **Hale** — per-record handler | 33.98 ms | 1.00× |
| **Hale** — `Drain<T>` batch | 34.36 ms | 1.01× |
| Go | 17.63 ms | 0.52× |
| Node | 106.06 ms | 3.12× † |
| Python | 346.66 ms | 10.20× |

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
it takes the small / dispatch-bound reader from 10.80 ms to **2.29 ms:
4.7× faster, and past Go's 2.61 ms.** That's the idiomatic Hale
consumer — a declarative `subscribe` plus an inline loop, no hand-rolled
mmap walk — so it's an apples-to-apples win on *both* ergonomics and raw
throughput. (`hale_drain` in `xproc/run.sh`; the per-record row is kept
for contrast.)

On the **large / copy-bound** variant the batch form is a wash (1.01×):
there the per-record cost is dominated by summing 512 fields, not by
dispatch, so eliminating the call changes nothing and Go stays ~1.9×
ahead. That remaining gap is now a *compute-codegen* question (Hale's
512 field loads + adds vs Go's), **not** a delivery-model one —
`Drain<T>` fixed the delivery model, which is all it was meant to do.
The honest read: on dispatch-bound delivery Hale is now fastest; on
compute-bound work over the payload there's a separate optimization gap
to bare-loop Go that batching doesn't touch.

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
**compute-bound** work over a large payload a separate codegen gap to
bare-loop Go remains (batching doesn't address it), and the array-field
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

## Three kinds of microbench

The benches under `micro/` split into **three categories**
answering different questions. Mix them with care — they're not
interchangeable.

### Overhead microbenches — "what does the substrate cost when unused?"

Strip allocation work down to nothing so the substrate machinery
runs alone. These deliberately measure Hale's worst case: the
arena lifecycle gets no chance to amortize against work it would
normally accompany.

- **`loop_overhead`** — empty while loop. No arena work at all.
- **`fn_call`** — `fn step(x) -> Int { return x * 2 + 1; }` called
  10M times: free-fn call overhead for a minimal *real* body. A free
  fn that allocates nothing skips its per-call scratch arena
  (`//go:noinline` on the Go sibling keeps it a fair real-call
  comparison). Before the 2026-06-28 allocation-classification work
  this body's `+` was treated as possibly-String-concat, so the call
  paid a scratch malloc/free (~10 ns/call); the type-aware `Add`
  classification recognizes `Int + Int` as arithmetic and now it runs
  at ~2 ns. (The earlier `return x;` body measured nothing — a bare
  identifier was always elided.)
- **`fn_modular`** — `outer(x) { return inner(x) * 3; }` over
  `inner(x) { return x + 1; }`, 10M times: the "is factoring a hot
  path into composed helpers free?" bench. Before the interprocedural
  non-allocating propagation (2026-06-28), *calling any function*
  marked the caller possibly-allocating, so `outer` paid a scratch
  malloc per call even though `inner` allocates nothing (~21 ns/call);
  the call-graph fixpoint now proves the whole chain non-allocating
  and it runs at ~4 ns. On factored code Hale went from ~13× Go's
  (no-inline) call overhead to ~2.5×.
- **`locus_instantiation`** — `Empty {}` 100k times,
  statement-position. Arena create + struct init + arena destroy
  with zero allocations in between.
- **`bus_dispatch`** — 10k typed messages through the bus. The
  per-message payload memcpy + queue enqueue is the design (per
  `memory.md` "pointers don't cross loci; values do") but the
  bench measures it isolated.
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
target-cpu + O3 defaults, `form_vec_push` is ~4.8× and
`form_vec_get` ~2.6× *faster* than Go. (An earlier note here
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
- **`coord_with_churn`** — chunked-class parent accepting K
  Worker children. Tests F.3 free-list reclamation + chunked
  sub-region allocator. (K capped at 20 by v1 codegen's
  accept() accumulation cliff at k≈25 — see comment in source.)

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
  where Hale decisively beats Node (8.6×) and Python (20.5×).**
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
│   ├── form_hashmap_false_sharing.{hl,go,js,py}
│   └── form_hashmap_walk_large.{hl,go,js,py}
├── app/
│   └── stream_aggregator.{ap,go,js,py}
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
4. Run `./run.sh --update-baselines` to seed.
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

## Known constraint — accumulation ceiling

Several Hale substrate paths segfault under v1 codegen
somewhere between 100k and 1M iterations of a tight loop. The
microbench Hale iteration counts are tuned **below** those
ceilings; comments inside each `.hl` document the threshold
they hit. The sibling `.go/.js/.py` benches mirror the same
iteration count so the ratio stays apples-to-apples.

The **`coord_with_churn`** bench hits the steepest cliff:
parent's `accept(child)` in a loop fails at k≈25 regardless of
projection class. Caps the bench at K=20, where the timing
signal is small but measurable. When the substrate
accumulation fix lands, raise iteration counts in all four
language files together.

## Future work

- **C twins for FORM-3.** `spec/forms.md` commits `@form(vec)`
  to within 10% of a hand-written C equivalent on push+get.
  Land C sources in `c-twins/` and add a comparison column
  to the runner's report.
- **More comparative langs.** Erlang (BEAM) is the natural fourth
  comparator since Hale's runtime model is BEAM-shaped. Rust
  is a fifth for the "non-GC compiled" point of comparison.
- **`hale bench` CLI.** Per `spec/testing.md`, this surface is
  planned but not shipped. The shell harness here is the current
  stand-in.
