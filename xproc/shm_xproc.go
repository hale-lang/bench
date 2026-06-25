// shm_xproc.go — Cross-process SHM delivery, idiomatic Go stdlib.
//
// One self-contained binary that re-execs itself to fork the
// producer child. Roles:
//
//   reader   (parent, default): creates the /dev/shm-backed file,
//            ftruncates it, mmaps it, spawns the producer child
//            (re-exec with `producer` argv), then spins on the
//            published write_seq, timing from the first record
//            (px=0) to the last (px=N-1). Prints iters / elapsed_ns.
//   producer (child): mmaps the same /dev/shm file and floods N
//            fixed 16-byte records (px = sequence, sz = px+1),
//            publishing each by an atomic store of write_seq.
//
// Shared memory is a real POSIX /dev/shm mmap (syscall.Mmap on a
// file under /dev/shm) — stdlib only: os, syscall, os/exec, time,
// sync/atomic, unsafe. Single-file `go build`.
//
// Layout: a header word holding the published write_seq (the count
// of records the producer has committed) followed by N slots of two
// int64s each. Sized for N records with no wrap, so no drops. The
// reader spins on an atomic load of write_seq (acquire) against the
// producer's atomic store (release), so it never reads a torn or
// uninitialized slot.
package main

import (
	"fmt"
	"os"
	"os/exec"
	"sync/atomic"
	"syscall"
	"time"
	"unsafe"
)

const (
	n        = 200000
	shmPath  = "/dev/shm/bench-shm-xproc-go"
	headerSz = 64 // cache-line-padded header holding write_seq at offset 0
	slotSz   = 16 // two int64s: px, sz
)

func mapSize() int { return headerSz + n*slotSz }

// mapShm opens (creating if asked) the /dev/shm file, sizes it, and
// mmaps it shared.
func mapShm(create bool) ([]byte, *os.File) {
	flag := os.O_RDWR
	if create {
		flag |= os.O_CREATE
	}
	f, err := os.OpenFile(shmPath, flag, 0o600)
	if err != nil {
		fatal("open shm: %v", err)
	}
	if create {
		if err := f.Truncate(int64(mapSize())); err != nil {
			fatal("ftruncate: %v", err)
		}
	}
	m, err := syscall.Mmap(int(f.Fd()), 0, mapSize(),
		syscall.PROT_READ|syscall.PROT_WRITE, syscall.MAP_SHARED)
	if err != nil {
		fatal("mmap: %v", err)
	}
	return m, f
}

func writeSeqPtr(m []byte) *int64 {
	return (*int64)(unsafe.Pointer(&m[0]))
}

func slotPtr(m []byte, i int) *[2]int64 {
	return (*[2]int64)(unsafe.Pointer(&m[headerSz+i*slotSz]))
}

func producer() {
	m, f := mapShm(false)
	defer f.Close()
	seq := writeSeqPtr(m)
	for i := 0; i < n; i++ {
		s := slotPtr(m, i)
		s[0] = int64(i)     // px
		s[1] = int64(i + 1) // sz
		// Release: publish this record's index. The reader's
		// acquire-load pairs with this so the slot writes above
		// are visible before the seq bump is.
		atomic.StoreInt64(seq, int64(i+1))
	}
}

func reader() {
	// Fresh file each run; ignore a stale one.
	_ = os.Remove(shmPath)
	m, f := mapShm(true)
	defer f.Close()
	defer os.Remove(shmPath)
	seq := writeSeqPtr(m)
	atomic.StoreInt64(seq, 0)

	self, err := os.Executable()
	if err != nil {
		fatal("executable: %v", err)
	}
	child := exec.Command(self, "producer")
	child.Stderr = os.Stderr
	if err := child.Start(); err != nil {
		fatal("start producer: %v", err)
	}

	// Wait for the first record (px=0 => write_seq reaches 1),
	// then start the clock; spin until all N are published.
	for atomic.LoadInt64(seq) < 1 {
	}
	t0 := time.Now()
	for atomic.LoadInt64(seq) < n {
	}
	elapsed := time.Since(t0).Nanoseconds()

	// Sanity: last slot carries the final record.
	last := slotPtr(m, n-1)
	if last[0] != int64(n-1) || last[1] != int64(n) {
		fatal("last record mismatch: px=%d sz=%d", last[0], last[1])
	}

	_ = child.Wait()
	fmt.Printf("iters=%d\n", n)
	fmt.Printf("elapsed_ns=%d\n", elapsed)
}

func fatal(format string, a ...interface{}) {
	fmt.Fprintf(os.Stderr, "shm_xproc.go: "+format+"\n", a...)
	os.Exit(1)
}

func main() {
	if len(os.Args) > 1 && os.Args[1] == "producer" {
		producer()
		return
	}
	reader()
}
