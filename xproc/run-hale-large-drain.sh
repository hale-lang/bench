#!/usr/bin/env bash
# run-hale-large-drain.sh — drive the two-process Hale shm-ring xproc bench.
#
# Starts the reader binary in the background (so its reader thread
# is polling), gives it a moment to attach, runs the producer to
# flood N records, waits for the reader, and prints its stdout
# (which carries `iters=` and `elapsed_ns=`).
#
# The shm name is fixed (`/bench-shm-xproc`); a stale object is
# rm -f'd before each run. atexit shm_unlink handles cleanup.
set -euo pipefail

XPROC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHM_NAME="bench-shm-xproc-large"

rm -f "/dev/shm/${SHM_NAME}" 2>/dev/null || true

READER="$XPROC_DIR/shm_xproc_large_reader_drain"
PRODUCER="$XPROC_DIR/shm_xproc_large_producer"
[ -x "$READER" ] || { echo "reader not built: $READER" >&2; exit 2; }
[ -x "$PRODUCER" ] || { echo "producer not built: $PRODUCER" >&2; exit 2; }

reader_out="$(mktemp)"
trap 'rm -f "$reader_out"' EXIT

"$READER" >"$reader_out" 2>/dev/null &
reader_pid=$!

# Let the reader create/attach the ring and start polling.
sleep 0.1

"$PRODUCER" >/dev/null 2>&1

wait "$reader_pid" 2>/dev/null || true

cat "$reader_out"
