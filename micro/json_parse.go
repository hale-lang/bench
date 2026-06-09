// Go equivalent of json_parse.hl — encoding/json struct unmarshal.
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
	body := []byte(`{"sym": "BTCUSD", "bid": 50000, "ask": 50010, "bidsz": 12, "asksz": 8, "ts": 1700000000000, "seq": 42}`)
	iters := 200000
	t0 := time.Now()
	var total int64
	for i := 0; i < iters; i++ {
		var q Quote
		if err := json.Unmarshal(body, &q); err != nil {
			panic(err)
		}
		total += q.Bid + q.Ask
	}
	elapsed := time.Since(t0).Nanoseconds()
	fmt.Printf("iters=%d\n", iters)
	fmt.Printf("total=%d\n", total)
	fmt.Printf("elapsed_ns=%d\n", elapsed)
}
