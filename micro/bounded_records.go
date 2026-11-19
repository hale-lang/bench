// Go equivalent of bounded_records.hl — fixed arrays of structs with a
// count, the closest Go shape to bounded[T; N]. Go strings are
// immutable and shared, so a struct copy copies no string bytes.
package main

import (
	"fmt"
	"time"
)

type Tag struct{ name string }
type Row struct {
	id    string
	tags  [4]Tag
	ntags int
}
type Rows struct {
	items [64]Row
	n     int
}
type Sum struct {
	id    string
	tags  [4]Tag
	ntags int
}
type Out struct {
	items [64]Sum
	n     int
}

func summaryOf(r Row) Sum { return Sum{id: r.id, tags: r.tags, ntags: r.ntags} }

func summaries(rs *Rows) *Out {
	out := &Out{}
	for i := 0; i < rs.n; i++ {
		out.items[out.n] = summaryOf(rs.items[i])
		out.n++
	}
	return out
}

//go:noinline
func round(k int) int {
	rs := &Rows{}
	for j := 0; j < 32; j++ {
		r := Row{id: fmt.Sprintf("row-%d-%d", k, j)}
		r.tags[0] = Tag{"red"}
		r.tags[1] = Tag{fmt.Sprintf("t%d", j)}
		r.ntags = 2
		rs.items[rs.n] = r
		rs.n++
	}
	for j := 0; j < 32; j++ {
		x := rs.items[j]
		x.id = x.id + "!"
		rs.items[j] = x
	}
	out := summaries(rs)
	n := 0
	for i := 0; i < out.n; i++ {
		n += len(out.items[i].id) + out.items[i].ntags
	}
	return n
}

func main() {
	rounds := 20000
	t0 := time.Now()
	total := 0
	for k := 0; k < rounds; k++ {
		total += round(k)
	}
	elapsed := time.Since(t0).Nanoseconds()
	fmt.Printf("rounds=%d\ntotal=%d\nelapsed_ns=%d\n", rounds, total, elapsed)
}
