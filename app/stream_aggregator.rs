// Rust equivalent of stream_aggregator.hl.
// Pub/sub aggregator: publisher fires N typed samples, an aggregator
// subscribes via subject-keyed dispatch (same shape as
// bus_dispatch.rs) and maintains running sum/min/max. The handler
// lookup is hoisted out of the loop, exactly like the .go.

#![allow(dead_code)]

use std::cell::Cell;
use std::collections::HashMap;
use std::time::Instant;

struct Sample {
    value: i64,
}

struct Aggregator {
    count: Cell<i64>,
    sum: Cell<i64>,
    min_v: Cell<i64>,
    max_v: Cell<i64>,
}

impl Aggregator {
    fn on_sample(&self, s: Sample) {
        self.count.set(self.count.get() + 1);
        self.sum.set(self.sum.get() + s.value);
        if s.value < self.min_v.get() {
            self.min_v.set(s.value);
        }
        if s.value > self.max_v.get() {
            self.max_v.set(s.value);
        }
    }
}

fn main() {
    let iters: i64 = 200000;
    let agg = Aggregator {
        count: Cell::new(0),
        sum: Cell::new(0),
        min_v: Cell::new(999999999),
        max_v: Cell::new(0),
    };
    let mut router: HashMap<&str, Box<dyn Fn(Sample) + '_>> = HashMap::new();
    router.insert("bench.sample", Box::new(|s| agg.on_sample(s)));

    let t0 = Instant::now();
    let handler = &router["bench.sample"];
    for i in 0..iters {
        let v = (i * 31 + 7) % 1000;
        handler(Sample { value: v });
    }
    let elapsed = t0.elapsed().as_nanos();

    println!("iters={}", iters);
    println!("count={}", agg.count.get());
    println!("sum={}", agg.sum.get());
    println!("elapsed_ns={}", elapsed);
}
