// Go equivalent of str_match.hl — a string `switch` with 16 cases.
package main

import (
	"fmt"
	"time"
)

//go:noinline
func arm(w string) int {
	switch w {
	case "alpha": return 1
	case "bravo": return 2
	case "charlie": return 3
	case "delta": return 4
	case "echo": return 5
	case "foxtrot": return 6
	case "golf": return 7
	case "hotel": return 8
	case "india": return 9
	case "juliett": return 10
	case "kilo": return 11
	case "lima": return 12
	case "mike": return 13
	case "november": return 14
	case "oscar": return 15
	case "papa": return 16
	}
	return 0
}

func main() {
	words := []string{"alpha", "bravo", "charlie", "delta", "echo", "foxtrot",
		"golf", "hotel", "india", "juliett", "kilo", "lima", "mike",
		"november", "oscar", "papa", "quebec"}
	iters := 2000000
	t0 := time.Now()
	sum := 0
	for i := 0; i < iters; i++ {
		sum += arm(words[i%17])
	}
	elapsed := time.Since(t0).Nanoseconds()
	fmt.Printf("iters=%d\nsum=%d\nelapsed_ns=%d\n", iters, sum, elapsed)
}
