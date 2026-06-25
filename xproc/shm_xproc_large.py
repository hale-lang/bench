#!/usr/bin/env python3
# shm_xproc_large.py — Cross-process SHM delivery, LARGE (~4 KB)
# payload, idiomatic CPython stdlib. Sibling of shm_xproc.py with a
# 4096-byte slot (512 int64s) and a reader that does real per-record
# work: sums all 512 int64s of every record into a checksum.
#
# os.fork() (child = producer, parent = reader), real /dev/shm stdlib
# mmap, published write_seq. Producer writes field[k] = i + k so the
# reader's checksum is verifiable.
#
# NOTE on "copy": the reader uses a memoryview.cast("q") over the mmap
# so the per-record slot is summed straight out of shared memory — no
# intermediate bytes copy. That is the fair analogue of Hale's
# in-place zero-copy read. (struct.unpack of each slot would force a
# 4 KB copy + 512-tuple build per record; the memoryview path avoids
# it.)
import mmap
import os
import struct
import time

N = 20000
FIELDS = 512
SHM_PATH = "/dev/shm/bench-shm-xproc-large-py"
HEADER_SZ = 64
SLOT_SZ = FIELDS * 8  # 4096
MAP_SIZE = HEADER_SZ + N * SLOT_SZ

_PACK = struct.Struct("<" + "q" * FIELDS)  # producer-side slot packer


def _read_seq(mm):
    return int.from_bytes(mm[0:8], "little", signed=True)


def _write_seq(mm, v):
    mm[0:8] = v.to_bytes(8, "little", signed=True)


def producer(mm):
    for i in range(N):
        off = HEADER_SZ + i * SLOT_SZ
        mm[off:off + SLOT_SZ] = _PACK.pack(*[i + k for k in range(FIELDS)])
        _write_seq(mm, i + 1)  # release-publish


def reader(mm, child_pid):
    # int64 view over the whole mapping (header included). Record i's
    # fields live at word index HEADER_WORDS + i*FIELDS .. +FIELDS.
    words = memoryview(mm).cast("q")
    header_words = HEADER_SZ // 8

    checksum = 0
    consumed = 0
    while _read_seq(mm) < 1:
        pass
    t0 = time.monotonic_ns()
    while consumed < N:
        pub = _read_seq(mm)
        while consumed < pub:
            base = header_words + consumed * FIELDS
            # Sum the record's fields straight out of the shared view.
            for k in range(FIELDS):
                checksum += words[base + k]
            consumed += 1
    elapsed = time.monotonic_ns() - t0

    os.waitpid(child_pid, 0)
    print(f"iters={N}")
    print(f"elapsed_ns={elapsed}")
    print(f"checksum={checksum}")


def main():
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
