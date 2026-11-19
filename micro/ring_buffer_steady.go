// Go equivalent of ring_buffer_steady.hl — a fixed array ring.
package main

import (
	"fmt"
	"strconv"
	"time"
)

type Sample struct {
	t, v int
	tag  string
}

type Ring struct {
	buf        [64]Sample
	head, size int
}

func (r *Ring) push(s Sample) bool {
	if r.size == 64 {
		return false
	}
	r.buf[(r.head+r.size)%64] = s
	r.size++
	return true
}

func (r *Ring) pop() (Sample, bool) {
	if r.size == 0 {
		return Sample{}, false
	}
	s := r.buf[r.head]
	r.buf[r.head] = Sample{}
	r.head = (r.head + 1) % 64
	r.size--
	return s, true
}

func main() {
	rounds := 2000000
	r := &Ring{}
	t0 := time.Now()
	for i := 0; i < 32; i++ {
		r.push(Sample{i, i % 7, "s" + strconv.Itoa(i%10)})
	}
	sum := 0
	for k := 0; k < rounds; k++ {
		r.push(Sample{k, k % 7, "s" + strconv.Itoa(k%10)})
		got, _ := r.pop()
		sum += got.v + len(got.tag)
	}
	elapsed := time.Since(t0).Nanoseconds()
	fmt.Printf("rounds=%d\nsum=%d\nelapsed_ns=%d\n", rounds, sum, elapsed)
}
