// shm_xproc_large.js — "Cross-process" SHM delivery, LARGE (~4 KB)
// payload, Node stdlib. Sibling of shm_xproc.js with a 4096-byte
// slot (512 int64s) and a reader that does real per-record work:
// sums all 512 BigInt64 fields of every record into a checksum.
//
// SAME HONEST CAVEAT as the 16-byte variant: Node has NO stdlib
// cross-PROCESS shared memory (no mmap / POSIX shm without a native
// addon, which this repo's no-extra-deps rule forbids). This uses
// `worker_threads` + a `SharedArrayBuffer`, which is shared memory
// between THREADS in one process, NOT between processes — a strictly
// weaker capability. The number is shown for honesty, not parity, and
// is not directly comparable to the Go/Python/Hale cross-process rows.
//
// Producer (worker) writes field[k] = i + k; reader (main) sums each
// record's fields straight out of the BigInt64Array view (in place,
// no per-record copy) and verifies the checksum.
'use strict';

const {
  Worker,
  isMainThread,
  workerData,
} = require('worker_threads');

const N = 20000;
const FIELDS = 512; // BigInt64 per record => 4096-byte slot
const HEADER_WORDS = 8; // write_seq at index 0
const TOTAL_WORDS = HEADER_WORDS + N * FIELDS;

function producer(view) {
  for (let i = 0; i < N; i++) {
    const base = HEADER_WORDS + i * FIELDS;
    for (let k = 0; k < FIELDS; k++) {
      view[base + k] = BigInt(i + k);
    }
    Atomics.store(view, 0, BigInt(i + 1)); // release-publish
  }
}

function reader() {
  const sab = new SharedArrayBuffer(TOTAL_WORDS * 8);
  const view = new BigInt64Array(sab);
  Atomics.store(view, 0, 0n);

  const worker = new Worker(__filename, { workerData: { sab } });

  let checksum = 0n;
  let consumed = 0;
  while (Atomics.load(view, 0) < 1n) {}
  const t0 = process.hrtime.bigint();
  while (consumed < N) {
    const pub = Number(Atomics.load(view, 0));
    while (consumed < pub) {
      const base = HEADER_WORDS + consumed * FIELDS;
      for (let k = 0; k < FIELDS; k++) {
        checksum += view[base + k]; // in-place read, no copy
      }
      consumed++;
    }
  }
  const elapsed = process.hrtime.bigint() - t0;

  worker.terminate().then(() => {
    console.log(`iters=${N}`);
    console.log(`elapsed_ns=${elapsed}`);
    console.log(`checksum=${checksum}`);
    // NOTE: same-process worker-thread shared memory, NOT
    // cross-process. See the file header for why.
  });
}

if (isMainThread) {
  reader();
} else {
  producer(new BigInt64Array(workerData.sab));
}
