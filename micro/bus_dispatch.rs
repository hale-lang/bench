// Rust equivalent of bus_dispatch.hl.
// Subject-keyed handler dispatch — a HashMap<&str, Box<dyn Fn>>
// lookup per publish, mirroring Hale's bus router. NOT channels:
// channels add buffering semantics Hale's in-scheduler bus doesn't
// have. NOT direct fn calls: those skip the subject match Hale pays
// for. Cell-based counter stands in for Go's mutable method value.

#![allow(dead_code)]

use std::cell::Cell;
use std::collections::HashMap;
use std::time::Instant;

struct Tick {
    n: i64,
}

struct Aggregator {
    count: Cell<i64>,
}

impl Aggregator {
    fn on_tick(&self, _t: Tick) {
        self.count.set(self.count.get() + 1);
    }
}

fn main() {
    let iters: i64 = 100000;
    let agg = Aggregator { count: Cell::new(0) };
    let mut router: HashMap<&str, Box<dyn Fn(Tick) + '_>> = HashMap::new();
    router.insert("bench.tick", Box::new(|t| agg.on_tick(t)));

    let t0 = Instant::now();
    for i in 0..iters {
        let handler = &router["bench.tick"];
        handler(Tick { n: i });
    }
    let elapsed = t0.elapsed().as_nanos();

    println!("iters={}", iters);
    println!("count={}", agg.count.get());
    println!("elapsed_ns={}", elapsed);
}
