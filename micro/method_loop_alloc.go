// Go equivalent of method_loop_alloc.hl.
// A method on a struct loops 10M times, formatting the counter into a
// fresh string each iteration and dropping it.
package main

import (
	"fmt"
	"strconv"
	"time"
)

type Bench struct {
	n int
}

//go:noinline
func (b *Bench) work() int {
	total := 0
	for i := 0; i < b.n; i++ {
		s := strconv.Itoa(i)
		total += len(s)
	}
	return total
}

func main() {
	b := &Bench{n: 10000000}
	t0 := time.Now()
	total := b.work()
	elapsed := time.Since(t0).Nanoseconds()
	fmt.Printf("n=%d\n", b.n)
	fmt.Printf("total=%d\n", total)
	fmt.Printf("elapsed_ns=%d\n", elapsed)
}
