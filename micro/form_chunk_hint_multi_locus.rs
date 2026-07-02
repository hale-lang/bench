// Rust equivalent of form_chunk_hint_multi_locus.hl.
// The .hl is a coverage bench for Hale's F.32-3 per-pool arena
// chunk-size hint (16 loci on one cooperative pool → 32 KB first
// chunks); Rust has no arena analogue, so this mirrors the workload
// shape only: 16 subscribers fanned out per tick via subject-keyed
// dispatch, 1000 ticks, then the same 200ms drain sleep inside the
// timed region — elapsed_ns is dominated by the sleep in both
// languages, so treat it as coverage, not a perf number.

#![allow(dead_code)]

use std::cell::Cell;
use std::collections::HashMap;
use std::thread;
use std::time::{Duration, Instant};

struct Tick {
    n: i64,
}

struct Worker {
    id: i64,
    tally: Cell<i64>,
}

impl Worker {
    fn on_tick(&self, t: &Tick) {
        self.tally.set(self.tally.get() + 1);
        if t.n == 0 {
            println!("worker {} alive", self.id);
        }
    }
}

fn main() {
    let workers: Vec<Worker> = (0..16)
        .map(|id| Worker {
            id,
            tally: Cell::new(0),
        })
        .collect();
    let mut router: HashMap<&str, &Vec<Worker>> = HashMap::new();
    router.insert("tick", &workers);

    let n_ticks: i64 = 1000;
    let t0 = Instant::now();
    for i in 0..n_ticks {
        let t = Tick { n: i };
        let subs = &router["tick"];
        for w in subs.iter() {
            w.on_tick(&t);
        }
    }
    // Let the "pool" drain, as the .hl does. 16 subscribers × 1000
    // ticks = 16000 handler invocations (already synchronous here).
    thread::sleep(Duration::from_millis(200));
    let elapsed = t0.elapsed().as_nanos();

    println!("n_ticks={}", n_ticks);
    println!("workers={}", 16);
    println!("elapsed_ns={}", elapsed);
}
