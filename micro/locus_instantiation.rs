// Rust equivalent of locus_instantiation.hl.
// Helper fn allocates Empty on the heap (Box), calls a method to
// return a field, XORs the result into a sink. Matches the Hale
// bench's shape so neither side gets DCE'd. black_box pins the Box —
// unlike Go's escape analysis, LLVM would otherwise stack-promote or
// elide the allocation entirely, and the point is heap-per-instance.

use std::hint::black_box;
use std::time::Instant;

struct Empty {
    v: i64,
}

impl Empty {
    #[inline(never)]
    fn read(&self) -> i64 {
        self.v
    }
}

#[inline(never)]
fn instantiate_one(seed: i64) -> i64 {
    let e = black_box(Box::new(Empty { v: seed }));
    e.read()
}

fn main() {
    let iters: i64 = 100000;
    let pid = std::process::id() as i64;
    let t0 = Instant::now();
    let mut sink: i64 = 0;
    for i in 0..iters {
        sink ^= instantiate_one(i + pid);
    }
    let elapsed = t0.elapsed().as_nanos();
    println!("iters={}", iters);
    println!("sink={}", sink);
    println!("elapsed_ns={}", elapsed);
}
