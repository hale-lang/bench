// Rust equivalent of tree_fanout.hl.
// Parent struct loops K times, constructs a Worker struct, invokes
// compute() on it (analogue of Hale's accept(w) → w.compute()),
// aggregates result. K=20 matches Hale's accept() cliff so the ratio
// stays apples-to-apples. Caveat: LLVM may fold compute()'s
// triangular sum to closed form where Go doesn't — the K×accept call
// structure is what's being mirrored.

#![allow(dead_code)]

use std::time::Instant;

struct Worker {
    id: i64,
    batch_size: i64,
}

impl Worker {
    #[inline(never)]
    fn compute(&self) -> i64 {
        let mut sum: i64 = 0;
        for i in 0..self.batch_size {
            sum += i;
        }
        sum
    }
}

struct Coordinator {
    num_workers: i64,
    items_each: i64,
    total: i64,
}

impl Coordinator {
    #[inline(never)]
    fn accept(&mut self, w: &Worker) {
        self.total += w.compute();
    }

    fn run(&mut self) {
        for i in 0..self.num_workers {
            let w = Worker {
                id: i,
                batch_size: self.items_each,
            };
            self.accept(&w);
        }
    }
}

fn main() {
    let k: i64 = 20;
    let m: i64 = 2000;
    let t0 = Instant::now();
    let mut c = Coordinator {
        num_workers: k,
        items_each: m,
        total: 0,
    };
    c.run();
    let elapsed = t0.elapsed().as_nanos();
    println!("k={}", k);
    println!("m={}", m);
    println!("total_ops={}", k * m);
    println!("total={}", c.total);
    println!("elapsed_ns={}", elapsed);
}
