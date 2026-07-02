// Rust equivalent of coord_with_churn.hl.
// Parent struct with a method that constructs + discards K heap
// Worker values (Box, mirroring the .go's escaping &Worker), invoking
// on_accept per child. Closest analog to Hale's chunked-class parent
// with accept(w: Worker). K=2000 matches the .go (the Hale bench's
// accept() ceiling caps at ~25 under v1 codegen). on_accept's body is
// black_box(w) rather than empty — unlike //go:noinline, LLVM would
// DCE a dead call to an empty inferred-pure fn and the alloc with it.

#![allow(dead_code)]

use std::hint::black_box;
use std::time::Instant;

struct Worker {
    n: i64,
}

struct Coord {
    batch: i64,
}

impl Coord {
    #[inline(never)]
    fn on_accept(&self, w: &Worker) {
        black_box(w);
    }

    #[inline(never)]
    fn run(&self) {
        for i in 0..self.batch {
            let w = Box::new(Worker { n: i });
            self.on_accept(&w);
        }
    }
}

fn main() {
    let k: i64 = 2000;
    let t0 = Instant::now();
    let c = Coord { batch: k };
    c.run();
    let elapsed = t0.elapsed().as_nanos();
    println!("k={}", k);
    println!("elapsed_ns={}", elapsed);
}
