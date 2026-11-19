#!/usr/bin/env bash
# run-unix-bus.sh — cross-process bus delivery over a unix socket.
#
# A publisher process floods N = 200000 small records (one Int) on a
# topic bound to a unix socket; a subscriber process, listening on it,
# times its first delivery to its last. The binding is a deployment
# choice, made here with LOTUS_BUS_CONFIG files rather than in the code:
# both programs are the same as they would be in one process. Two modes:
#   default : the binding as a program gets it
#   stream  : LOTUS_UNIX_STREAM=1, the framed stream mode
# Each is run ITERS times (default 10); prints the median ms and the
# records per second. Hale-only: the bus binding is Hale's; the SHM
# tables in run.sh compare languages over shared memory instead.
set -euo pipefail

XPROC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ITERS="${ITERS:-10}"
N=200000

if [[ -n "${HALE_BIN:-}" ]]; then HALE="$HALE_BIN"
elif command -v hale >/dev/null 2>&1; then HALE="$(command -v hale)"
else HALE="$XPROC_DIR/../../hale/target/release/hale"; fi

( cd "$XPROC_DIR" && "$HALE" build unix_bus_sub.hl >/dev/null 2>&1 && "$HALE" build unix_bus_pub.hl >/dev/null 2>&1 ) \
    || { echo "run-unix-bus.sh: hale build failed" >&2; exit 1; }

WORK="$(mktemp -d)"
SUB_PID=""
trap '[ -n "$SUB_PID" ] && kill "$SUB_PID" 2>/dev/null; rm -rf "$WORK"' EXIT

one() {
    local stream="$1" sock="$WORK/bus.sock" out
    rm -f "$sock"
    echo "bench.unix = unix://$sock : listen" >"$WORK/sub.conf"
    echo "bench.unix = unix://$sock : connect" >"$WORK/pub.conf"
    LOTUS_UNIX_STREAM="$stream" LOTUS_BUS_CONFIG="$WORK/sub.conf" \
        "$XPROC_DIR/unix_bus_sub" "$N" >"$WORK/sub.out" 2>/dev/null &
    SUB_PID=$!
    for _ in $(seq 200); do [ -S "$sock" ] && break; sleep 0.01; done
    LOTUS_UNIX_STREAM="$stream" LOTUS_BUS_CONFIG="$WORK/pub.conf" \
        "$XPROC_DIR/unix_bus_pub" "$N" >/dev/null 2>&1
    wait "$SUB_PID" 2>/dev/null || true
    SUB_PID=""
    out="$(cat "$WORK/sub.out")"
    if ! grep -q "count=$N" <<<"$out"; then
        echo "run-unix-bus.sh: the subscriber got $(grep -oE 'count=[0-9]+' <<<"$out")" >&2
        return 1
    fi
    grep -oE 'elapsed_ns=[0-9]+' <<<"$out" | cut -d= -f2
}

median() { printf '%s\n' "$@" | sort -n | sed -n "$(( ($# + 1) / 2 ))p"; }

echo
echo "Cross-process bus over unix:// — N=$N one-Int records  (ITERS=$ITERS)"
printf '%-10s %12s %14s\n' "mode" "median_ms" "records_per_s"
printf '%-10s %12s %14s\n' "----" "---------" "-------------"
for mode in default stream; do
    if [ "$mode" = stream ]; then s=1; else s=""; fi
    runs=()
    for ((i = 1; i <= ITERS; i++)); do runs+=("$(one "$s")"); done
    m="$(median "${runs[@]}")"
    printf '%-10s %12s %14s\n' "$mode" \
        "$(awk -v v="$m" 'BEGIN { printf "%.3f", v / 1e6 }')" \
        "$(awk -v v="$m" -v n="$N" 'BEGIN { printf "%.0f", n / (v / 1e9) }')"
done
