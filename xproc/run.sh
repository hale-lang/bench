#!/usr/bin/env bash
# run.sh — cross-process SHM delivery comparative runner.
#
# Builds (where needed) and runs each language's xproc bench ITERS
# times, takes the median elapsed_ns, and prints a small table:
# language, median ms, ratio_vs_hale (= sibling_median / hale_median).
#
# Two variants, reported as separate tables:
#   small : N=200000 fixed 16-byte records (dispatch-bound; payload
#           copy-vs-zero-copy is noise, per-record delivery dominates).
#   large : N=20000  ~4 KB records, reader sums the WHOLE payload per
#           record (copy-bound; this is where zero-copy read should
#           pay off — and the variant that exposed Hale's array-field
#           layout caveat; see README).
#
# This is a SEPARATE bench from the main grid. It is NOT auto-run by
# the top-level run.sh and does not gate anything; it lives entirely
# under xproc/.
#
# Stdlib-only siblings, single-file builds:
#   hale   : two binaries (reader + producer) over a real /dev/shm
#            shm_ring, driven by run-hale*.sh.
#   go     : one self-re-exec binary, real /dev/shm mmap (syscall).
#   python : os.fork() + stdlib mmap over /dev/shm.
#   node   : worker_threads + SharedArrayBuffer (SAME-process threads,
#            NOT cross-process — Node has no stdlib mmap/shm; see the
#            shm_xproc*.js headers). Shown for honesty, not parity.
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
HALE_OK=0
if [ -x "$HALE" ]; then
  if ( cd "$XPROC_DIR" \
        && "$HALE" build shm_xproc_reader.hl >/dev/null 2>&1 \
        && "$HALE" build shm_xproc_reader_drain.hl >/dev/null 2>&1 \
        && "$HALE" build shm_xproc_producer.hl >/dev/null 2>&1 \
        && "$HALE" build shm_xproc_large_reader.hl >/dev/null 2>&1 \
        && "$HALE" build shm_xproc_large_reader_drain.hl >/dev/null 2>&1 \
        && "$HALE" build shm_xproc_large_producer.hl >/dev/null 2>&1 ); then
    HALE_OK=1
  else
    echo "hale build failed" >&2
  fi
else
  echo "hale CLI not found at $HALE — skipping Hale" >&2
fi

GO_OK=0
if have go; then
  if ( cd "$XPROC_DIR" \
        && go build -o shm_xproc.go.bin shm_xproc.go \
        && go build -o shm_xproc_large.go.bin shm_xproc_large.go ); then
    GO_OK=1
  else
    echo "go build failed" >&2
  fi
fi

# --- run phase -------------------------------------------------------
# Per-variant median maps, addressed as MED_<variant>[<lang>].
declare -A MED_small
declare -A MED_large

run_lang() {
  local variant="$1"; local lang="$2"; shift 2
  local samples=()
  local s out
  for ((s = 0; s < ITERS; s++)); do
    out="$("$@" 2>/dev/null | extract || true)"
    [ -n "$out" ] && samples+=("$out")
  done
  if [ "${#samples[@]}" -gt 0 ]; then
    local m; m="$(median "${samples[@]}")"
    eval "MED_${variant}[$lang]=\"$m\""
  fi
}

# small (16-byte) variant
[ "$HALE_OK" -eq 1 ] && run_lang small hale       "$XPROC_DIR/run-hale.sh"
[ "$HALE_OK" -eq 1 ] && run_lang small hale_drain "$XPROC_DIR/run-hale-drain.sh"
[ "$GO_OK"   -eq 1 ] && run_lang small go     "$XPROC_DIR/shm_xproc.go.bin"
have python3         && run_lang small python python3 "$XPROC_DIR/shm_xproc.py"
have node            && run_lang small node   node    "$XPROC_DIR/shm_xproc.js"

# large (~4 KB) variant
[ "$HALE_OK" -eq 1 ] && run_lang large hale       "$XPROC_DIR/run-hale-large.sh"
[ "$HALE_OK" -eq 1 ] && run_lang large hale_drain "$XPROC_DIR/run-hale-large-drain.sh"
[ "$GO_OK"   -eq 1 ] && run_lang large go     "$XPROC_DIR/shm_xproc_large.go.bin"
have python3         && run_lang large python python3 "$XPROC_DIR/shm_xproc_large.py"
have node            && run_lang large node   node    "$XPROC_DIR/shm_xproc_large.js"

# --- report ----------------------------------------------------------
ms() { awk -v ns="$1" 'BEGIN { printf "%.3f", ns / 1e6 }'; }
ratio() {
  local v="$1"; local h="$2"
  [ -n "$h" ] && [ -n "$v" ] \
    && awk -v a="$v" -v h="$h" 'BEGIN { printf "%.2fx", a / h }' \
    || printf '—'
}

print_table() {
  local variant="$1"; local title="$2"
  local -n MED="MED_${variant}"
  local hale_med="${MED[hale]:-}"
  echo
  echo "$title  (ITERS=$ITERS)"
  printf '%-10s %12s %14s\n' "language" "median_ms" "ratio_vs_hale"
  printf '%-10s %12s %14s\n' "--------" "---------" "-------------"
  local lang m
  for lang in hale hale_drain go node python; do
    m="${MED[$lang]:-}"
    if [ -n "$m" ]; then
      printf '%-10s %12s %14s\n' "$lang" "$(ms "$m")" "$(ratio "$m" "$hale_med")"
    else
      printf '%-10s %12s %14s\n' "$lang" "n/a" "—"
    fi
  done
}

print_table small "Cross-process SHM delivery — SMALL: N=200000, 16-byte records"
print_table large "Cross-process SHM delivery — LARGE: N=20000, ~4 KB records (reader sums whole payload)"

echo
echo "note: node = SAME-process worker_threads + SharedArrayBuffer"
echo "      (no stdlib cross-process shm in Node); not directly comparable."
echo "note: large variant — Hale's payload is a flat 512-scalar-field"
echo "      struct, NOT a [Int; N] array field (arrays lower to an"
echo "      out-of-line pointer that dangles cross-process). See README."
