// Go equivalent of coord_with_churn.hl.
// Parent struct with a method that constructs + discards K
// Worker values, invoking onAccept per child. Closest analog
// to Hale's chunked-class parent with accept(w: Worker).
// Note: K=2000 because the Hale bench's accept() ceiling
// caps at ~25 under v1 codegen; raising K here would unbalance
// the ratio.
package main

import (
	"fmt"
	"time"
)

type Worker struct {
	n int
}

type Coord struct {
	batch int
}

//go:noinline
func (c *Coord) onAccept(w *Worker) {}

//go:noinline
func (c *Coord) run() {
	for i := 0; i < c.batch; i++ {
		w := &Worker{n: i}
		c.onAccept(w)
	}
}

func main() {
	k := 2000
	t0 := time.Now()
	c := &Coord{batch: k}
	c.run()
	elapsed := time.Since(t0).Nanoseconds()
	fmt.Printf("k=%d\n", k)
	fmt.Printf("elapsed_ns=%d\n", elapsed)
}
