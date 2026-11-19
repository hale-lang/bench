// Go equivalent of str_csv_sum.hl — strings.Split + strconv.Atoi.
package main

import (
	"fmt"
	"strconv"
	"strings"
	"time"
)

func main() {
	var b strings.Builder
	for i := 0; i < 1000; i++ {
		fmt.Fprintf(&b, "%d,17,4,250,9,33,1024,%d\n", i, i%7)
	}
	csv := b.String()
	rounds := 100
	t0 := time.Now()
	total := 0
	for r := 0; r < rounds; r++ {
		for _, line := range strings.Split(strings.TrimSuffix(csv, "\n"), "\n") {
			for _, f := range strings.Split(line, ",") {
				v, err := strconv.Atoi(f)
				if err != nil {
					v = 0
				}
				total += v
			}
		}
	}
	elapsed := time.Since(t0).Nanoseconds()
	fmt.Printf("rounds=%d\ntotal=%d\nelapsed_ns=%d\n", rounds, total, elapsed)
}
