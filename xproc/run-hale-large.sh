#!/usr/bin/env bash
# run-hale-large.sh — drive the LARGE-payload two-process Hale shm bench.
#
# Same shape as run-hale.sh but for the ~4 KB-payload variant: starts
# the reader (its reader thread polls), waits, runs the producer, then
# prints the reader's stdout (iters / elapsed_ns / checksum).
set -euo pipefail

XPROC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHM_NAME="bench-shm-xproc-large"

rm -f "/dev/shm/${SHM_NAME}" 2>/dev/null || true

READER="$XPROC_DIR/shm_xproc_large_reader"
PRODUCER="$XPROC_DIR/shm_xproc_large_producer"
[ -x "$READER" ] || { echo "reader not built: $READER" >&2; exit 2; }
[ -x "$PRODUCER" ] || { echo "producer not built: $PRODUCER" >&2; exit 2; }

reader_out="$(mktemp)"
trap 'rm -f "$reader_out"' EXIT

"$READER" >"$reader_out" 2>/dev/null &
reader_pid=$!

sleep 0.1
"$PRODUCER" >/dev/null 2>&1
wait "$reader_pid" 2>/dev/null || true

cat "$reader_out"
