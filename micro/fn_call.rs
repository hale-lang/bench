// Rust equivalent of fn_call.hl. Free-fn call overhead, minimal body.
// #[inline(never)] forces a real call; unlike //go:noinline, LLVM still
// DCEs dead calls to fns it infers as pure, so each result is pinned
// with black_box to keep the call live every iteration.

use std::hint::black_box;
use std::time::Instant;

#[inline(never)]
fn step(x: i64) -> i64 {
    x * 2 + 1
}

fn main() {
    let iters: i64 = 10000000;
    let t0 = Instant::now();
    let mut acc: i64 = 0;
    for i in 0..iters {
        acc = black_box(step(i));
    }
    let elapsed = t0.elapsed().as_nanos();
    println!("iters={}", iters);
    println!("acc={}", acc);
    println!("elapsed_ns={}", elapsed);
}
