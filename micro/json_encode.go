// Go equivalent of json_encode.hl — encoding/json struct marshal.
package main

import (
	"encoding/json"
	"fmt"
	"time"
)

type Quote struct {
	Sym   string `json:"sym"`
	Bid   int64  `json:"bid"`
	Ask   int64  `json:"ask"`
	Bidsz int64  `json:"bidsz"`
	Asksz int64  `json:"asksz"`
	Ts    int64  `json:"ts"`
	Seq   int64  `json:"seq"`
}

func main() {
	iters := 200000
	t0 := time.Now()
	total := 0
	for i := 0; i < iters; i++ {
		q := Quote{Sym: "BTCUSD", Bid: 50000, Ask: 50010, Bidsz: 12, Asksz: 8, Ts: 1700000000000, Seq: int64(i)}
		b, err := json.Marshal(&q)
		if err != nil {
			panic(err)
		}
		total += len(b)
	}
	elapsed := time.Since(t0).Nanoseconds()
	fmt.Printf("iters=%d\n", iters)
	fmt.Printf("total=%d\n", total)
	fmt.Printf("elapsed_ns=%d\n", elapsed)
}
