#!/usr/bin/env bash
# run.sh — cross-process SHM delivery comparative runner.
#
# Builds (where needed) and runs each language's xproc bench ITERS
# times, takes the median elapsed_ns, and prints a small table:
# language, median ms, ratio_vs_hale (= sibling_median / hale_median).
#
# This is a SEPARATE bench from the main grid. It is NOT auto-run by
# the top-level run.sh and does not gate anything; it lives entirely
# under xproc/.
#
# Stdlib-only siblings, single-file builds:
#   hale   : two binaries (reader + producer) over a real /dev/shm
#            shm_ring, driven by run-hale.sh.
#   go     : one self-re-exec binary, real /dev/shm mmap (syscall).
#   python : os.fork() + stdlib mmap over /dev/shm.
#   node   : worker_threads + SharedArrayBuffer (SAME-process threads,
#            NOT cross-process — Node has no stdlib mmap/shm; see
#            shm_xproc.js header). Shown for honesty, not parity.
set -euo pipefail

XPROC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ITERS="${ITERS:-10}"

if [[ -n "${HALE_BIN:-}" ]]; then
  HALE="$HALE_BIN"
elif command -v hale >/dev/null 2>&1; then
  HALE="$(command -v hale)"
else
  HALE="$XPROC_DIR/../../hale/target/release/hale"
fi

have() { command -v "$1" >/dev/null 2>&1; }

median() {
  local sorted n mid
  sorted=$(printf '%s\n' "$@" | sort -n)
  n=$(printf '%s\n' "$sorted" | wc -l)
  mid=$(( (n + 1) / 2 ))
  printf '%s\n' "$sorted" | sed -n "${mid}p"
}

# Extract elapsed_ns from a bench's stdout.
extract() { grep -oE 'elapsed_ns=[0-9]+' | head -1 | cut -d= -f2; }

# --- build phase -----------------------------------------------------
echo "building..." >&2
if [ -x "$HALE" ]; then
  ( cd "$XPROC_DIR" && "$HALE" build shm_xproc_reader.hl >/dev/null 2>&1 \
      && "$HALE" build shm_xproc_producer.hl >/dev/null 2>&1 ) \
    && HALE_OK=1 || { echo "hale build failed" >&2; HALE_OK=0; }
else
  echo "hale CLI not found at $HALE — skipping Hale" >&2
  HALE_OK=0
fi

if have go; then
  ( cd "$XPROC_DIR" && go build -o shm_xproc.go.bin shm_xproc.go ) \
    && GO_OK=1 || { echo "go build failed" >&2; GO_OK=0; }
else
  GO_OK=0
fi

# --- run phase -------------------------------------------------------
declare -A MED
run_lang() {
  local lang="$1"; shift
  local samples=()
  local s out
  for ((s = 0; s < ITERS; s++)); do
    out="$("$@" 2>/dev/null | extract || true)"
    [ -n "$out" ] && samples+=("$out")
  done
  if [ "${#samples[@]}" -gt 0 ]; then
    MED[$lang]="$(median "${samples[@]}")"
  fi
}

[ "${HALE_OK:-0}" -eq 1 ] && run_lang hale "$XPROC_DIR/run-hale.sh"
[ "${GO_OK:-0}" -eq 1 ]   && run_lang go "$XPROC_DIR/shm_xproc.go.bin"
have python3 && run_lang python python3 "$XPROC_DIR/shm_xproc.py"
have node    && run_lang node node "$XPROC_DIR/shm_xproc.js"

# --- report ----------------------------------------------------------
hale_med="${MED[hale]:-}"

ms() { awk -v ns="$1" 'BEGIN { printf "%.3f", ns / 1e6 }'; }
ratio() {
  [ -n "$hale_med" ] && [ -n "$1" ] \
    && awk -v a="$1" -v h="$hale_med" 'BEGIN { printf "%.2fx", a / h }' \
    || printf '—'
}

echo
echo "Cross-process SHM delivery — N=200000 16-byte records, ITERS=$ITERS"
printf '%-10s %12s %14s\n' "language" "median_ms" "ratio_vs_hale"
printf '%-10s %12s %14s\n' "--------" "---------" "-------------"
for lang in hale go node python; do
  m="${MED[$lang]:-}"
  if [ -n "$m" ]; then
    printf '%-10s %12s %14s\n' "$lang" "$(ms "$m")" "$(ratio "$m")"
  else
    printf '%-10s %12s %14s\n' "$lang" "n/a" "—"
  fi
done
echo
echo "note: node = SAME-process worker_threads + SharedArrayBuffer"
echo "      (no stdlib cross-process shm in Node); not directly comparable."
