#!/usr/bin/env bash
# gates/run.sh — the v1 gate measures: what the Hale toolchain costs and
# what a served program does, as opposed to the substrate primitives
# micro/ isolates.
#
#   build   `hale build` wall time and peak RSS: cold (empty runtime-
#           object cache), warm (unchanged rebuild) and after a one-line
#           edit, on a small program and on the largest one in the hale
#           tree (dna/host).
#   http    gates/http_serve.hl under gates/httpload.rs, a closed-loop
#           HTTP/1.1 load generator: requests/s, p50 and p99 at 1, 16 and
#           64 connections, with errors and dropped attempts counted.
#   memory  the same server under 16 connections of constant load: its
#           RSS every second, and the growth after the first 10 s.
#   lsp     gates/lsp_latency.py driving `hale lsp`: open-to-diagnostics
#           and edit-to-diagnostics on a small seed and a large one, and
#           the server's peak RSS.
#   api     gates/rpc_serve.hl, one @rpc method served over unix::Rpc,
#           under gates/rpcload.rs (closed loop, JSON-line calls): calls/s,
#           p50 and p99 at 1 and 16 connections.
#   hub     gates/hub_serve.hl, a ws::Hub, fanning a topic out to 1, 16
#           and 64 websocket clients (gates/wsload.rs): deliveries/s for a
#           burst of 10,000 ticks, and per-delivery latency with ticks
#           1 ms apart.
#   startup binary size of the three servers, and spawn to first
#           answered request for http_serve.
#   pg      gates/pq_bench.hl, the pure-Hale `pq` client on a pool, against
#           a throwaway postgres:16 container this script starts and
#           removes by name (needs docker; skipped, and said so, without):
#           SELECT 1, a point lookup, and a one-INSERT transaction with
#           the commit flushed and with it asynchronous.
#
# It MEASURES ONLY. There are no tolerance bands here and no number
# fails the run: these measures are recorded so that v1 targets can be
# chosen against them (hale-lang/hale#1950), and a later release
# compared with this one. Exit is non-zero only when something did not
# build or run.
#
# Usage:
#   gates/run.sh                      # all of them, ~16 min
#   gates/run.sh --only=build,lsp     # a subset of build,http,memory,lsp,api,hub,startup,pg
#   gates/run.sh --reps=N             # repeats of each http, api and hub measure (default 5; pg 3)
#   gates/run.sh --build-reps=N       # repeats of each build measure (default 3)
#   gates/run.sh --memory-seconds=N   # the memory run's length (default 120)
#   gates/run.sh --record             # also write the medians to baselines.json's "gates"
#                                     # (replacing only the areas this run measured)
#   gates/run.sh --json               # quieter; JSON-only stdout
#
# The hale binary resolves as run.sh's does (HALE_BIN, then
# ../hale/target/release/hale, then PATH). The build and editor measures
# read programs from a hale checkout, HALE_SRC: by default the checkout
# HALE_BIN sits in (<checkout>/target/release/hale), else ../hale. The
# checkout is only read: builds run on a copy in a temporary directory.
#
# Needs jq, /usr/bin/time, python3 (the LSP client and a free port) and
# rustc (the load generators), all of them stdlib-only; docker for pg.

set -euo pipefail

GATES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCH_DIR="$(dirname "$GATES_DIR")"

for arg in "$@"; do
    case "$arg" in
        -h|--help) awk 'NR > 1 && !/^#/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "${BASH_SOURCE[0]}"; exit 0 ;;
    esac
done

if [[ -n "${HALE_BIN:-}" ]]; then
    HALE="$HALE_BIN"
elif [[ -x "$BENCH_DIR/../hale/target/release/hale" ]]; then
    HALE="$BENCH_DIR/../hale/target/release/hale"
elif command -v hale >/dev/null 2>&1; then
    HALE="$(command -v hale)"
else
    echo "gates/run.sh: no hale binary found (no HALE_BIN, no sibling" >&2
    echo "  ../hale/target/release/hale, none on PATH)" >&2
    exit 1
fi
HALE="$(cd "$(dirname "$HALE")" && pwd)/$(basename "$HALE")"
[ -x "$HALE" ] || { echo "gates/run.sh: not executable: $HALE" >&2; exit 1; }

if [[ -z "${HALE_SRC:-}" ]]; then
    guess="$(dirname "$(dirname "$(dirname "$HALE")")")"
    if [[ -d "$guess/dna/host" ]]; then HALE_SRC="$guess"
    else HALE_SRC="$BENCH_DIR/../hale"; fi
fi
HALE_SRC="$(cd "$HALE_SRC" 2>/dev/null && pwd)" || { echo "gates/run.sh: HALE_SRC is not a directory" >&2; exit 1; }

ONLY="build,http,memory,lsp,api,hub,startup,pg"
REPS=5
BUILD_REPS=3
MEMORY_SECONDS=120
RECORD=0
JSON_ONLY=0
for arg in "$@"; do
    case "$arg" in
        --only=*)           ONLY="${arg#--only=}" ;;
        --reps=*)           REPS="${arg#--reps=}" ;;
        --build-reps=*)     BUILD_REPS="${arg#--build-reps=}" ;;
        --memory-seconds=*) MEMORY_SECONDS="${arg#--memory-seconds=}" ;;
        --record)           RECORD=1 ;;
        --json)             JSON_ONLY=1 ;;
        *)                  echo "unknown arg: $arg" >&2; exit 2 ;;
    esac
done
wants() { [[ ",$ONLY," == *",$1,"* ]]; }
log() { [ "$JSON_ONLY" -eq 1 ] || echo "$@" >&2; }

command -v jq >/dev/null || { echo "jq not found on PATH" >&2; exit 2; }
command -v /usr/bin/time >/dev/null || { echo "/usr/bin/time not found" >&2; exit 2; }
command -v python3 >/dev/null || { echo "python3 not found on PATH" >&2; exit 2; }
if wants http || wants memory || wants api || wants hub || wants startup; then
    command -v rustc >/dev/null || { echo "rustc not found on PATH (it builds gates/httpload.rs)" >&2; exit 2; }
fi

# The references. Paths are relative to HALE_SRC.
BUILD_SMALL="crates/hale-codegen/tests/fixtures/examples/92-build-an-api"
BUILD_LARGE="dna/host"
LSP_SMALL="crates/hale-codegen/tests/fixtures/examples/92-build-an-api/main.hl"
LSP_LARGE="dna/core/assembly.hl"

WORK="$(mktemp -d)"
SERVER_PID=""
PG_NAME=""
cleanup() {
    if [ -n "$SERVER_PID" ]; then kill "$SERVER_PID" 2>/dev/null || true; wait "$SERVER_PID" 2>/dev/null || true; fi
    if [ -n "$PG_NAME" ]; then docker rm -f -v "$PG_NAME" >/dev/null 2>&1 || true; fi
    rm -rf "$WORK"
}
trap cleanup EXIT

hale_version="$("$HALE" --version 2>/dev/null | awk 'NR == 1 {print $2}')"
hale_commit="$(git -C "$HALE_SRC" rev-parse --short=9 HEAD 2>/dev/null || echo unknown)"
cpu="$(awk -F': ' '/^model name/ {print $2; exit}' /proc/cpuinfo)"
cores="$(awk -F': ' '/^cpu cores/ {print $2; exit}' /proc/cpuinfo)"
threads="$(nproc)"
mem_gib="$(awk '/^MemTotal/ {printf "%d", $2 / 1048576 + 0.5}' /proc/meminfo)"
log "hale: $HALE (hale $hale_version), sources: $HALE_SRC at $hale_commit"
log "machine: $cpu, $cores cores / $threads threads, $mem_gib GiB, Linux $(uname -r)"

# jq: median (the lower middle for an even count, as run.sh's), min,
# max and every run, of an array of numbers.
STATS='def stats: sort as $s | {median: $s[((length - 1) / 2 | floor)], min: $s[0], max: $s[-1], runs: .};'

now_ns() { date +%s%N; }

# Runs a command; prints "<wall seconds> <peak RSS KiB>". Its output goes
# to $WORK/last.log, shown when it fails.
timed() {
    local t0 t1
    t0=$(now_ns)
    if ! /usr/bin/time -f '%M' -o "$WORK/rss" "$@" >"$WORK/last.log" 2>&1; then
        echo "gates/run.sh: failed: $*" >&2
        cat "$WORK/last.log" >&2
        exit 1
    fi
    t1=$(now_ns)
    awk -v a="$t0" -v b="$t1" -v r="$(tail -1 "$WORK/rss")" 'BEGIN { printf "%.2f %d\n", (b - a) / 1e9, r }'
}

# ---- build ---------------------------------------------------------------

bench_build() {
    local out="{}" name rel src target t rss cold warm edit peak
    for name in small large; do
        if [ "$name" = small ]; then rel="$BUILD_SMALL"; else rel="$BUILD_LARGE"; fi
        cold=(); warm=(); edit=(); peak=()
        for ((r = 1; r <= BUILD_REPS; r++)); do
            log "[build/$name] run $r/$BUILD_REPS"
            src="$WORK/src"; rm -rf "$src" "$WORK/cache"; mkdir -p "$src" "$WORK/cache"
            # The large program imports its siblings by relative path
            # (../core, ../operations, ../../iris/...), so the whole of
            # dna/ and iris/ is copied.
            if [ "$name" = large ]; then
                cp -r "$HALE_SRC/dna" "$src/dna"; cp -r "$HALE_SRC/iris" "$src/iris"; target="$src/$rel"
            else
                cp -r "$HALE_SRC/$rel" "$src/prog"; target="$src/prog"
            fi
            read -r t rss < <(timed env XDG_CACHE_HOME="$WORK/cache" HALE_SKIP_STALE_CHECK=1 "$HALE" build "$target" -o "$WORK/out")
            cold+=("$t"); peak+=("$rss")
            read -r t rss < <(timed env XDG_CACHE_HOME="$WORK/cache" HALE_SKIP_STALE_CHECK=1 "$HALE" build "$target" -o "$WORK/out")
            warm+=("$t")
            echo "// bench edit" >> "$target/main.hl"
            read -r t rss < <(timed env XDG_CACHE_HOME="$WORK/cache" HALE_SKIP_STALE_CHECK=1 "$HALE" build "$target" -o "$WORK/out")
            edit+=("$t")
        done
        out=$(jq --arg n "$name" --arg tgt "$rel" \
            --argjson c "$(printf '%s\n' "${cold[@]}" | jq -s .)" \
            --argjson w "$(printf '%s\n' "${warm[@]}" | jq -s .)" \
            --argjson e "$(printf '%s\n' "${edit[@]}" | jq -s .)" \
            --argjson p "$(printf '%s\n' "${peak[@]}" | jq -s 'map(. / 1024 | round)')" \
            "$STATS"' . + {($n): {target: $tgt, cold_s: ($c | stats), warm_s: ($w | stats),
                edit_s: ($e | stats), peak_rss_mib: ($p | stats)}}' <<<"$out")
    done
    echo "$out"
}

# ---- http and memory -------------------------------------------------------

free_port() {
    python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])'
}

build_server() {
    [ -x "$WORK/http_serve" ] && return 0
    log "[http] building gates/http_serve.hl and gates/httpload.rs"
    timed env HALE_SKIP_STALE_CHECK=1 "$HALE" build "$GATES_DIR/http_serve.hl" --target-cpu native -o "$WORK/http_serve" >/dev/null
    rustc -O --edition 2021 "$GATES_DIR/httpload.rs" -o "$WORK/httpload"
}

# Starts the server on a fresh port and waits until it accepts.
PORT=""
start_server() {
    PORT=$(free_port)
    "$WORK/http_serve" "$PORT" >/dev/null 2>&1 &
    SERVER_PID=$!
    local i
    for ((i = 0; i < 400; i++)); do
        if (exec 3<>"/dev/tcp/127.0.0.1/$PORT") 2>/dev/null; then return 0; fi
        sleep 0.05
    done
    echo "gates/run.sh: the HTTP server did not come up on $PORT" >&2
    exit 1
}

stop_server() {
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
    SERVER_PID=""
}

rss_kib() { awk '/^VmRSS:/ {print $2}' "/proc/$1/status"; }

bench_http() {
    build_server
    local out="{}" c r runs
    for c in 1 16 64; do
        runs="[]"
        for ((r = 1; r <= REPS; r++)); do
            log "[http/$c] run $r/$REPS"
            start_server
            runs=$(jq --argjson x "$("$WORK/httpload" --addr "127.0.0.1:$PORT" --conns "$c" --duration 10 --warmup 2)" \
                '. + [$x]' <<<"$runs")
            stop_server
        done
        out=$(jq --arg k "conns_$c" --argjson runs "$runs" "$STATS"' . + {($k): {
            rps: ($runs | map(.rps) | stats), p50_us: ($runs | map(.p50_us) | stats),
            p99_us: ($runs | map(.p99_us) | stats),
            errors: ($runs | map(.errors) | add), dropped: ($runs | map(.dropped) | add),
            reconnects: ($runs | map(.reconnects) | add)}}' <<<"$out")
    done
    echo "$out"
}

bench_memory() {
    build_server
    log "[memory] ${MEMORY_SECONDS} s under 16 connections"
    start_server
    local idle t0 load_pid samples="$WORK/rss.samples" after
    idle=$(rss_kib "$SERVER_PID")
    "$WORK/httpload" --addr "127.0.0.1:$PORT" --conns 16 --duration "$MEMORY_SECONDS" --warmup 0 >"$WORK/load.json" &
    load_pid=$!
    t0=$(now_ns)
    : >"$samples"
    while kill -0 "$load_pid" 2>/dev/null; do
        echo "$(awk -v a="$t0" -v b="$(now_ns)" 'BEGIN { printf "%.1f", (b - a) / 1e9 }') $(rss_kib "$SERVER_PID")" >>"$samples"
        sleep 1
    done
    wait "$load_pid"
    after=$(rss_kib "$SERVER_PID")
    stop_server
    # least-squares slope of RSS over time, after the first 10 s
    awk -v idle="$idle" -v after="$after" -v secs="$MEMORY_SECONDS" '
        { t[NR] = $1; r[NR] = $2 }
        END {
            n = 0; st = 0; sr = 0
            for (i = 1; i <= NR; i++) if (t[i] >= 10) { n++; st += t[i]; sr += r[i] }
            mt = st / n; mr = sr / n; num = 0; den = 0
            for (i = 1; i <= NR; i++) if (t[i] >= 10) { num += (t[i] - mt) * (r[i] - mr); den += (t[i] - mt) ^ 2 }
            at10 = r[1]; best = 1e9
            for (i = 1; i <= NR; i++) { d = t[i] - 10; if (d < 0) d = -d; if (d < best) { best = d; at10 = r[i] } }
            printf "{\"seconds\": %d, \"conns\": 16, \"rss_mib_idle\": %.1f, \"rss_mib_at_10s\": %.1f, \"rss_mib_at_end\": %.1f, \"rss_mib_after_load\": %.1f, \"growth_kib_per_min_after_10s\": %.1f}\n",
                secs, idle / 1024, at10 / 1024, r[NR] / 1024, after / 1024, (den > 0 ? num / den : 0) * 60
        }' "$samples" \
    | jq --slurpfile load "$WORK/load.json" --rawfile s "$samples" \
        '. + {requests: $load[0].requests, errors: $load[0].errors, dropped: $load[0].dropped,
              samples: ($s | split("\n") | map(select(length > 0) | split(" ") | map(tonumber)))}'
}

# ---- editor ------------------------------------------------------------------

bench_lsp() {
    local out="{}" name rel
    for name in small_seed large_seed; do
        if [ "$name" = small_seed ]; then rel="$LSP_SMALL"; else rel="$LSP_LARGE"; fi
        log "[lsp/$name] $rel"
        out=$(jq --arg n "$name" --arg f "$rel" \
            --argjson r "$(cd "$HALE_SRC" && python3 "$GATES_DIR/lsp_latency.py" "$HALE" "$rel" --edits 20)" \
            '. + {($n): ($r + {file: $f})}' <<<"$out")
    done
    echo "$out"
}

# ---- api: @rpc over a unix socket ------------------------------------------------

build_tool() {  # $1 = gates/<name>.rs
    [ -x "$WORK/$1" ] || rustc -O --edition 2021 "$GATES_DIR/$1.rs" -o "$WORK/$1"
}

build_hl() {  # $1 = gates/<name>.hl
    [ -x "$WORK/$1" ] || timed env HALE_SKIP_STALE_CHECK=1 "$HALE" build "$GATES_DIR/$1.hl" --target-cpu native -o "$WORK/$1" >/dev/null
}

bench_api() {
    log "[api] building gates/rpc_serve.hl and gates/rpcload.rs"
    build_hl rpc_serve; build_tool rpcload
    local out="{}" c r runs sock="$WORK/rpc.sock" i
    for c in 1 16; do
        runs="[]"
        for ((r = 1; r <= REPS; r++)); do
            log "[api/$c] run $r/$REPS"
            rm -f "$sock"
            "$WORK/rpc_serve" "$sock" >/dev/null 2>&1 &
            SERVER_PID=$!
            for ((i = 0; i < 400; i++)); do [ -S "$sock" ] && break; sleep 0.05; done
            runs=$(jq --argjson x "$("$WORK/rpcload" --path "$sock" --conns "$c" --duration 10 --warmup 2)" '. + [$x]' <<<"$runs")
            stop_server
        done
        out=$(jq --arg k "conns_$c" --argjson runs "$runs" "$STATS"' . + {($k): {
            rps: ($runs | map(.rps) | stats), p50_us: ($runs | map(.p50_us) | stats),
            p99_us: ($runs | map(.p99_us) | stats),
            errors: ($runs | map(.errors) | add), dropped: ($runs | map(.dropped) | add)}}' <<<"$out")
    done
    echo "$out"
}

# ---- hub: ws::Hub fan-out ----------------------------------------------------------

bench_hub() {
    log "[hub] building gates/hub_serve.hl and gates/wsload.rs"
    build_hl hub_serve; build_tool wsload
    local out="{}" c r runs mode m i ctl="$WORK/ctl"
    mkdir -p "$ctl"
    for mode in burst paced; do
        local clients="1 16 64" msgs=10000 flag=""
        if [ "$mode" = paced ]; then clients="1 64"; msgs=500; flag="--pace"; fi
        for c in $clients; do
            runs="[]"
            for ((r = 1; r <= REPS; r++)); do
                log "[hub/$mode/$c] run $r/$REPS"
                rm -f "$ctl/cmd"
                PORT=$(free_port)
                "$WORK/hub_serve" "$PORT" "$ctl" >/dev/null 2>&1 &
                SERVER_PID=$!
                for ((i = 0; i < 400; i++)); do
                    if (exec 3<>"/dev/tcp/127.0.0.1/$PORT") 2>/dev/null; then break; fi
                    sleep 0.05
                done
                runs=$(jq --argjson x "$("$WORK/wsload" --addr "127.0.0.1:$PORT" --clients "$c" --messages "$msgs" --ctl "$ctl" $flag)" '. + [$x]' <<<"$runs")
                echo stop >"$ctl/cmd"
                stop_server
            done
            out=$(jq --arg k "${mode}_$c" --argjson runs "$runs" "$STATS"' . + {($k): {
                messages: $runs[0].messages, clients: $runs[0].clients,
                deliveries_per_s: ($runs | map(.deliveries_per_s) | stats),
                p50_us: ($runs | map(.p50_us) | stats), p99_us: ($runs | map(.p99_us) | stats),
                dropped: ($runs | map(.dropped) | add), refused: ($runs | map(.refused_upgrades) | add)}}' <<<"$out")
        done
    done
    echo "$out"
}

# ---- startup -----------------------------------------------------------------------

bench_startup() {
    build_server; build_hl rpc_serve; build_hl hub_serve
    log "[startup] spawn to first answer, 11 runs"
    local runs=() r
    for ((r = 1; r <= 11; r++)); do
        runs+=("$("$WORK/httpload" --startup "$WORK/http_serve" | jq .startup_us)")
    done
    jq -n --argjson s "$(printf '%s\n' "${runs[@]}" | jq -s .)" \
        --argjson h "$(stat -c %s "$WORK/http_serve")" --argjson p "$(stat -c %s "$WORK/rpc_serve")" \
        --argjson u "$(stat -c %s "$WORK/hub_serve")" \
        "$STATS"'{first_answer_us: ($s | stats), size_bytes: {http_serve: $h, rpc_serve: $p, hub_serve: $u}}'
}

# ---- pg: pq on a pool, against a throwaway postgres ----------------------------------

bench_pg() {
    if ! command -v docker >/dev/null || ! docker info >/dev/null 2>&1; then
        log "[pg] skipped: no usable docker"
        echo '{"skipped": "no usable docker"}'
        return 0
    fi
    log "[pg] building gates/pq_bench.hl with the tree's pond/pq"
    local dir="$WORK/pg" r i runs="[]"
    mkdir -p "$dir/pond"
    cp -r "$HALE_SRC/dna/core/pond/pq" "$HALE_SRC/dna/core/pond/db" "$dir/pond/"
    cp "$GATES_DIR/pq_bench.hl" "$dir/"
    timed env HALE_SKIP_STALE_CHECK=1 "$HALE" build "$dir/pq_bench.hl" --target-cpu native -o "$dir/pq_bench" >/dev/null
    PG_NAME="hale-bench-pg-$$"
    PORT=$(free_port)
    log "[pg] starting $PG_NAME (postgres:16) on 127.0.0.1:$PORT"
    docker run -d --rm --name "$PG_NAME" -e POSTGRES_USER=bench -e POSTGRES_PASSWORD=bench \
        -e POSTGRES_DB=bench -p "127.0.0.1:$PORT:5432" postgres:16 >/dev/null
    for ((i = 0; i < 120; i++)); do
        docker exec "$PG_NAME" pg_isready -U bench -h 127.0.0.1 >/dev/null 2>&1 && break
        sleep 0.5
    done
    sleep 1
    for ((r = 1; r <= 3; r++)); do
        log "[pg] run $r/3"
        runs=$(jq --argjson x "$("$dir/pq_bench" "$PORT" 20000 | awk '
            { name = $1; for (i = 2; i <= NF; i++) { split($i, kv, "="); v[name, kv[1]] = kv[2] } names[++k] = name }
            END { printf "{"; for (j = 1; j <= k; j++) { n = names[j]; printf "%s\"%s\": {\"n\": %s, \"ok\": %s, \"us_per_op\": %.1f}", (j > 1 ? ", " : ""), n, v[n, "n"], v[n, "ok"], v[n, "ns_per_op"] / 1000 } printf "}\n" }')" \
            '. + [$x]' <<<"$runs")
    done
    docker rm -f -v "$PG_NAME" >/dev/null 2>&1 || true
    PG_NAME=""
    jq "$STATS"' . as $runs | ($runs[0] | keys) as $ks
        | reduce $ks[] as $k ({}; . + {($k): {us_per_op: ($runs | map(.[$k].us_per_op) | stats),
              n: $runs[0][$k].n, failed: ($runs | map(.[$k].n - .[$k].ok) | add)}})
        | . + {image: "postgres:16", pool_size: 2}' <<<"$runs"
}

# ---- run and report ------------------------------------------------------------

report=$(jq -n --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg v "$hale_version" --arg c "$hale_commit" \
    --arg cpu "$cpu" --argjson cores "$cores" --argjson threads "$threads" --argjson mem "$mem_gib" \
    --arg k "$(uname -r)" --argjson reps "$REPS" --argjson breps "$BUILD_REPS" \
    '{generated_at: $t, hale_version: $v, hale_commit: $c,
      machine: {cpu: $cpu, cores: $cores, threads: $threads, mem_gib: $mem, kernel: $k},
      reps: $reps, build_reps: $breps}')
for m in build http memory lsp api hub startup pg; do
    wants "$m" || continue
    # Into a file, not $(...): a command substitution is a subshell, and
    # the server it starts would escape the EXIT trap on a failure.
    "bench_$m" >"$WORK/$m.json"
    report=$(jq --arg m "$m" --slurpfile x "$WORK/$m.json" '. + {($m): $x[0]}' <<<"$report")
done

mkdir -p "$BENCH_DIR/results"
results_path="$BENCH_DIR/results/gates-$(date -u +%Y%m%d-%H%M%S).json"
echo "$report" >"$results_path"

# The flat view: one row per measure, as README's table and baselines.json
# record it.
FLAT='
  def row($area; $what; $s; $unit): {area: $area, measure: $what, unit: $unit, median: $s.median, min: $s.min, max: $s.max};
  def one($area; $what; $v; $unit): {area: $area, measure: $what, unit: $unit, median: $v};
  [ (.build // {} | to_entries[] | .value as $b | ($b.target) as $t |
        row("build"; "\($t), cold"; $b.cold_s; "s"),
        row("build"; "\($t), warm, unchanged"; $b.warm_s; "s"),
        row("build"; "\($t), after a one-line edit"; $b.edit_s; "s"),
        row("build"; "\($t), cold, peak RSS"; $b.peak_rss_mib; "MiB")),
    (.http // {} | to_entries[] | .value as $h | (.key | ltrimstr("conns_")) as $c |
        row("http"; "\($c) conn, requests/s"; $h.rps; "req/s"),
        row("http"; "\($c) conn, p50"; $h.p50_us; "µs"),
        row("http"; "\($c) conn, p99"; $h.p99_us; "µs"),
        one("http"; "\($c) conn, errors / dropped, all runs"; "\($h.errors) / \($h.dropped)"; "")),
    (.memory // empty | . as $m |
        one("memory"; "server RSS idle"; $m.rss_mib_idle; "MiB"),
        one("memory"; "server RSS at 10 s"; $m.rss_mib_at_10s; "MiB"),
        one("memory"; "server RSS at \($m.seconds) s"; $m.rss_mib_at_end; "MiB"),
        one("memory"; "RSS growth after 10 s (\($m.requests) requests, \($m.errors) errors, \($m.dropped) dropped)"; $m.growth_kib_per_min_after_10s; "KiB/min")),
    (.lsp // {} | to_entries[] | .value as $l | (.key | sub("_"; " ")) as $n |
        one("editor"; "\($n) (\($l.file)): open to diagnostics"; $l.open_done_ms; "ms"),
        one("editor"; "\($n): edit to diagnostics, p50"; $l.edit_done_ms_p50; "ms"),
        one("editor"; "\($n): edit to diagnostics, p95"; $l.edit_done_ms_p95; "ms"),
        one("editor"; "\($n): server peak RSS"; $l.peak_rss_mib; "MiB")),
    (.api // {} | to_entries[] | .value as $h | (.key | ltrimstr("conns_")) as $c |
        row("api"; "unix rpc, \($c) conn, calls/s"; $h.rps; "calls/s"),
        row("api"; "unix rpc, \($c) conn, p50"; $h.p50_us; "µs"),
        row("api"; "unix rpc, \($c) conn, p99"; $h.p99_us; "µs"),
        one("api"; "unix rpc, \($c) conn, errors / dropped, all runs"; "\($h.errors) / \($h.dropped)"; "")),
    (.hub // {} | to_entries[] | .value as $h | (.key | split("_")) as $k |
        if $k[0] == "burst" then
            row("hub"; "burst of \($h.messages) to \($h.clients) clients, deliveries/s"; $h.deliveries_per_s; "/s"),
            one("hub"; "burst to \($h.clients) clients, dropped / refused, all runs"; "\($h.dropped) / \($h.refused)"; "")
        else
            row("hub"; "paced, \($h.clients) clients, delivery p50"; $h.p50_us; "µs"),
            row("hub"; "paced, \($h.clients) clients, delivery p99"; $h.p99_us; "µs")
        end),
    (.startup // empty | . as $s |
        row("startup"; "http_serve: spawn to first answer"; $s.first_answer_us; "µs"),
        one("startup"; "binary size: http_serve / rpc_serve / hub_serve"; "\($s.size_bytes.http_serve / 1048576 * 100 | round / 100) / \($s.size_bytes.rpc_serve / 1048576 * 100 | round / 100) / \($s.size_bytes.hub_serve / 1048576 * 100 | round / 100)"; "MiB")),
    (.pg // empty | if .skipped then one("pg"; "skipped"; .skipped; "") else
        (to_entries[] | select(.value | type == "object" and has("us_per_op")) | .key as $k | .value as $v |
            row("pg"; "\($k) (\($v.n) ops, \($v.failed) failed)"; $v.us_per_op; "µs/op")) end)
  ]'

if [ "$RECORD" -eq 1 ]; then
    tmp="$WORK/baselines.json"
    # rows of the areas this run measured replace those areas' rows; the
    # other areas' rows stay, each stamped with the version it measured
    jq --argjson r "$report" --argjson rows "$(jq "$FLAT" <<<"$report")" \
        '($rows | map(.area) | unique) as $areas
         | ($rows | map(. + {hale_version: $r.hale_version, hale_commit: $r.hale_commit})) as $new
         | .gates = {updated_at: $r.generated_at, hale_version: $r.hale_version, hale_commit: $r.hale_commit,
                   machine: ($r.machine | del(.kernel)), reps: $r.reps, build_reps: $r.build_reps,
                   note: "measured only; these are not tolerance bands and run.sh does not read them",
                   measures: (((.gates.measures // []) | map(select(.area as $a | $areas | index($a) | not))) + $new)}' \
        "$BENCH_DIR/baselines.json" >"$tmp"
    mv "$tmp" "$BENCH_DIR/baselines.json"
    log "recorded into baselines.json (.gates)"
fi

if [ "$JSON_ONLY" -eq 1 ]; then
    echo "$report"
else
    log ""
    log "| Area | Measure | Median | Range |"
    log "|---|---|---|---|"
    jq -r "$FLAT"' | .[] | "| \(.area) | \(.measure) | \(.median) \(.unit) | \(if .min then "\(.min) to \(.max)" else "" end) |"' <<<"$report" >&2
    log ""
    log "Report: $results_path"
fi
