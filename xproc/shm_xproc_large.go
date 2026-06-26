// shm_xproc_large.go — Cross-process SHM delivery, LARGE (~4 KB)
// payload, idiomatic Go stdlib. Sibling of shm_xproc.go but with a
// 4096-byte slot (512 int64s) and a reader that does real per-record
// work: it sums all 512 int64s of every record into a checksum, so
// copy-vs-read actually matters and the work can't be elided.
//
// Self-re-exec fork (parent = reader, child = producer), real
// /dev/shm syscall.Mmap, published write_seq the reader spins on.
// Stdlib only. The producer writes the pattern field[k] = i + k so
// the reader's checksum can be verified.
//
// NOTE on "copy": Go reads the slot through an unsafe slice over the
// mmap and sums in place — it does NOT memcpy the 4 KB into a fresh
// buffer first. That is the fair analogue of Hale's zero-copy
// in-place read. (A deserialize-into-struct reader would add a 4 KB
// copy per record; this reader avoids it, same as Hale.)
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
	nLarge   = 20000
	fields   = 512 // int64s per record => 4096-byte slot
	shmLarge = "/dev/shm/bench-shm-xproc-large-go"
	hdrLarge = 64 // header holding write_seq at offset 0
	slotLg   = fields * 8
)

func mapSizeLg() int { return hdrLarge + nLarge*slotLg }

func mapShmLg(create bool) ([]byte, *os.File) {
	flag := os.O_RDWR
	if create {
		flag |= os.O_CREATE
	}
	f, err := os.OpenFile(shmLarge, flag, 0o600)
	if err != nil {
		fatalLg("open shm: %v", err)
	}
	if create {
		if err := f.Truncate(int64(mapSizeLg())); err != nil {
			fatalLg("ftruncate: %v", err)
		}
	}
	m, err := syscall.Mmap(int(f.Fd()), 0, mapSizeLg(),
		syscall.PROT_READ|syscall.PROT_WRITE, syscall.MAP_SHARED)
	if err != nil {
		fatalLg("mmap: %v", err)
	}
	return m, f
}

func seqPtrLg(m []byte) *int64 { return (*int64)(unsafe.Pointer(&m[0])) }

// slotLgView returns the record's 512 int64s as a slice aliasing the
// mmap in place (no copy).
func slotLgView(m []byte, i int) []int64 {
	base := unsafe.Pointer(&m[hdrLarge+i*slotLg])
	return unsafe.Slice((*int64)(base), fields)
}

func producerLg() {
	m, f := mapShmLg(false)
	defer f.Close()
	seq := seqPtrLg(m)
	for i := 0; i < nLarge; i++ {
		s := slotLgView(m, i)
		for k := 0; k < fields; k++ {
			s[k] = int64(i + k)
		}
		atomic.StoreInt64(seq, int64(i+1)) // release-publish
	}
}

func readerLg() {
	_ = os.Remove(shmLarge)
	m, f := mapShmLg(true)
	defer f.Close()
	defer os.Remove(shmLarge)
	seq := seqPtrLg(m)
	atomic.StoreInt64(seq, 0)

	self, err := os.Executable()
	if err != nil {
		fatalLg("executable: %v", err)
	}
	child := exec.Command(self, "producer")
	child.Stderr = os.Stderr
	if err := child.Start(); err != nil {
		fatalLg("start producer: %v", err)
	}

	var checksum int64
	var consumed int64
	// Wait for the first record, start the clock.
	for atomic.LoadInt64(seq) < 1 {
	}
	t0 := time.Now()
	for consumed < nLarge {
		pub := atomic.LoadInt64(seq)
		for consumed < pub {
			s := slotLgView(m, int(consumed)) // in-place, no copy
			for k := 0; k < fields; k++ {
				checksum += s[k]
			}
			consumed++
		}
	}
	elapsed := time.Since(t0).Nanoseconds()

	_ = child.Wait()
	fmt.Printf("iters=%d\n", nLarge)
	fmt.Printf("elapsed_ns=%d\n", elapsed)
	fmt.Printf("checksum=%d\n", checksum)
}

func fatalLg(format string, a ...interface{}) {
	fmt.Fprintf(os.Stderr, "shm_xproc_large.go: "+format+"\n", a...)
	os.Exit(1)
}

func main() {
	if len(os.Args) > 1 && os.Args[1] == "producer" {
		producerLg()
		return
	}
	readerLg()
}
