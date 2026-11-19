// Go equivalent of str_concat_loop.hl — strings.Builder (Go's `s += "ab"`
// copies the whole string each time, which is not how Go builds one).
package main

import (
	"fmt"
	"strings"
	"time"
)

func main() {
	iters := 1000000
	t0 := time.Now()
	var b strings.Builder
	for i := 0; i < iters; i++ {
		b.WriteString("ab")
	}
	s := b.String()
	elapsed := time.Since(t0).Nanoseconds()
	fmt.Printf("iters=%d\nlen=%d\nelapsed_ns=%d\n", iters, len(s), elapsed)
}
