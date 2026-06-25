// shm_xproc.js — "Cross-process" SHM delivery, Node stdlib.
//
// HONEST CAVEAT: Node.js has NO stdlib cross-PROCESS shared memory.
// There is no built-in mmap / POSIX shm; real /dev/shm sharing
// between OS processes needs a native addon (e.g. an mmap N-API
// module), which violates this repo's "shell + jq, no extra build
// dependencies" rule. So unlike the Go and Python siblings — which
// do real /dev/shm mmap between separate processes — this entry uses
// the closest stdlib-only analogue: `worker_threads` + a
// `SharedArrayBuffer`. That is shared memory between THREADS in one
// process, NOT between processes. It is a strictly weaker capability
// and the numbers are not directly comparable to the cross-process
// siblings; treat this row as "Node's best stdlib shared-memory
// answer," with the gap itself being the finding.
//
//   producer: a worker thread that writes N fixed 16-byte records
//             (px = sequence, sz = px+1) into the SAB ring, publishing
//             each via Atomics.store on a header write_seq word.
//   reader:   the main thread spins on Atomics.load of write_seq,
//             timing from the first record (px=0) to the last
//             (px=N-1). Prints iters / elapsed_ns.
//
// Layout mirrors the Go/Python siblings: an 8-int64 header (write_seq
// in slot 0) then N slots of two int64s (px, sz), over a single
// BigInt64Array view of the SharedArrayBuffer. Atomics.store/load
// give the release/acquire pairing so the reader never sees a torn
// or unpublished slot.
'use strict';

const {
  Worker,
  isMainThread,
  workerData,
} = require('worker_threads');

const N = 200000;
const HEADER_WORDS = 8; // write_seq at index 0 (cache-line pad)
const SLOT_WORDS = 2; // px, sz
const TOTAL_WORDS = HEADER_WORDS + N * SLOT_WORDS;

function producer(view) {
  for (let i = 0; i < N; i++) {
    const base = HEADER_WORDS + i * SLOT_WORDS;
    view[base] = BigInt(i); // px
    view[base + 1] = BigInt(i + 1); // sz
    // Release: publish the committed count. Pairs with the reader's
    // Atomics.load acquire so the two writes above are visible first.
    Atomics.store(view, 0, BigInt(i + 1));
  }
}

function reader() {
  const sab = new SharedArrayBuffer(TOTAL_WORDS * 8);
  const view = new BigInt64Array(sab);
  Atomics.store(view, 0, 0n);

  const worker = new Worker(__filename, { workerData: { sab } });

  // Wait for the first record, start the clock, spin until all N.
  while (Atomics.load(view, 0) < 1n) {}
  const t0 = process.hrtime.bigint();
  while (Atomics.load(view, 0) < BigInt(N)) {}
  const elapsed = process.hrtime.bigint() - t0;

  // Sanity: last slot carries the final record.
  const lastBase = HEADER_WORDS + (N - 1) * SLOT_WORDS;
  if (view[lastBase] !== BigInt(N - 1) || view[lastBase + 1] !== BigInt(N)) {
    console.error(
      `last record mismatch: px=${view[lastBase]} sz=${view[lastBase + 1]}`
    );
    process.exit(1);
  }

  worker.terminate().then(() => {
    console.log(`iters=${N}`);
    console.log(`elapsed_ns=${elapsed}`);
    // NOTE: same-process worker-thread shared memory, NOT
    // cross-process. See the file header for why.
  });
}

if (isMainThread) {
  reader();
} else {
  producer(new BigInt64Array(workerData.sab));
}
