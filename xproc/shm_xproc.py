#!/usr/bin/env python3
# shm_xproc.py — Cross-process SHM delivery, idiomatic CPython stdlib.
#
# os.fork() splits the process: the child is the producer, the
# parent is the reader. Shared memory is a real POSIX /dev/shm mmap
# (stdlib `mmap` over a file under /dev/shm) — no third-party deps.
#
#   producer (child): writes N fixed 16-byte records (px = sequence,
#            sz = px+1) into the ring, publishing each by storing the
#            committed count (write_seq) into the header word.
#   reader   (parent): spins on the published write_seq, timing from
#            the first record (px=0) to the last (px=N-1). Prints
#            iters / elapsed_ns to stdout.
#
# Layout matches the Go sibling: a 64-byte header whose first 8 bytes
# hold write_seq (the count of records committed), then N slots of two
# int64s each. Sized for N with no wrap, so no drops.
#
# CPython has no atomic primitives over a raw mmap, but on x86-64 an
# aligned native-word store/load is atomic and the GIL plus the
# little-endian int64 we round-trip via `struct`/int.from_bytes keep
# the write_seq publish coherent. The reader only ever reads a slot
# once write_seq has advanced past it, so it never sees a torn slot.
import mmap
import os
import struct
import time

N = 200000
SHM_PATH = "/dev/shm/bench-shm-xproc-py"
HEADER_SZ = 64       # write_seq lives in the first 8 bytes
SLOT_SZ = 16         # two int64s: px, sz
MAP_SIZE = HEADER_SZ + N * SLOT_SZ

_REC = struct.Struct("<qq")   # little-endian px, sz


def _read_seq(mm):
    return int.from_bytes(mm[0:8], "little", signed=True)


def _write_seq(mm, v):
    mm[0:8] = v.to_bytes(8, "little", signed=True)


def producer(mm):
    for i in range(N):
        off = HEADER_SZ + i * SLOT_SZ
        mm[off:off + SLOT_SZ] = _REC.pack(i, i + 1)
        # Publish: bump the committed count. The slot bytes above are
        # written before this store, so a reader that observes the
        # bumped count sees a fully-written slot.
        _write_seq(mm, i + 1)


def reader(mm, child_pid):
    # Wait for the first record (write_seq >= 1), start the clock,
    # spin until all N are committed.
    while _read_seq(mm) < 1:
        pass
    t0 = time.monotonic_ns()
    while _read_seq(mm) < N:
        pass
    elapsed = time.monotonic_ns() - t0

    # Sanity: last slot carries the final record.
    off = HEADER_SZ + (N - 1) * SLOT_SZ
    px, sz = _REC.unpack(mm[off:off + SLOT_SZ])
    if px != N - 1 or sz != N:
        raise SystemExit(f"last record mismatch: px={px} sz={sz}")

    os.waitpid(child_pid, 0)
    print(f"iters={N}")
    print(f"elapsed_ns={elapsed}")


def main():
    # Fresh backing file each run.
    try:
        os.remove(SHM_PATH)
    except FileNotFoundError:
        pass
    fd = os.open(SHM_PATH, os.O_CREAT | os.O_RDWR, 0o600)
    os.ftruncate(fd, MAP_SIZE)
    mm = mmap.mmap(fd, MAP_SIZE, mmap.MAP_SHARED,
                   mmap.PROT_READ | mmap.PROT_WRITE)
    os.close(fd)
    _write_seq(mm, 0)

    pid = os.fork()
    if pid == 0:
        # Child: producer. Inherits the same mapping.
        producer(mm)
        os._exit(0)
    else:
        try:
            reader(mm, pid)
        finally:
            mm.close()
            try:
                os.remove(SHM_PATH)
            except FileNotFoundError:
                pass


if __name__ == "__main__":
    main()
