// Rust equivalent of bus_dispatch_heap_payload.hl.
// Same shape as bus_dispatch.rs but the payload carries a String
// field: a fresh heap String is built per publish and dropped by the
// subscriber, standing in for Hale's str-clone-into-subscriber-arena
// wire-codec path. Caveat: Rust moves ownership through the dyn call
// (one alloc + one free per message), where Hale pays a codec
// serialize/deserialize; iters=50000 matches the .hl's halved count.

#![allow(dead_code)]

use std::cell::Cell;
use std::collections::HashMap;
use std::time::Instant;

struct Beat {
    n: i64,
    label: String,
}

struct Counter {
    count: Cell<i64>,
}

impl Counter {
    fn on_beat(&self, _b: Beat) {
        self.count.set(self.count.get() + 1);
    }
}

fn main() {
    let iters: i64 = 50000;
    let c = Counter { count: Cell::new(0) };
    let mut router: HashMap<&str, Box<dyn Fn(Beat) + '_>> = HashMap::new();
    router.insert("bench.beat.heap", Box::new(|b| c.on_beat(b)));

    let t0 = Instant::now();
    for i in 0..iters {
        let handler = &router["bench.beat.heap"];
        handler(Beat {
            n: i,
            label: String::from("tick"),
        });
    }
    let elapsed = t0.elapsed().as_nanos();

    println!("iters={}", iters);
    println!("count={}", c.count.get());
    println!("elapsed_ns={}", elapsed);
}
