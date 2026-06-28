// Go equivalent of fn_modular.hl — helper calls helper. //go:noinline
// on both so it measures real call-chain overhead, not a folded loop.
package main

import (
	"fmt"
	"time"
)

//go:noinline
func inner(x int) int { return x + 1 }

//go:noinline
func outer(x int) int { return inner(x) * 3 }

func main() {
	iters := 10000000
	t0 := time.Now()
	acc := 0
	for i := 0; i < iters; i++ {
		acc = outer(i)
	}
	elapsed := time.Since(t0).Nanoseconds()
	fmt.Printf("iters=%d\n", iters)
	fmt.Printf("acc=%d\n", acc)
	fmt.Printf("elapsed_ns=%d\n", elapsed)
}
