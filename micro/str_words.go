// Go equivalent of str_words.hl — strings.Fields over the same text.
package main

import (
	"fmt"
	"strings"
	"time"
)

func main() {
	text := strings.Repeat("the quick brown fox jumps over a lazy dog and runs ", 200)
	rounds := 500
	t0 := time.Now()
	n := 0
	for r := 0; r < rounds; r++ {
		for _, w := range strings.Fields(text) {
			if len(w) > 3 {
				n++
			}
		}
	}
	elapsed := time.Since(t0).Nanoseconds()
	fmt.Printf("rounds=%d\ncount=%d\nelapsed_ns=%d\n", rounds, n, elapsed)
}
