// Rust equivalent of fn_modular.hl — helper calls helper. #[inline(never)]
// on both so it measures real call-chain overhead, not a folded loop.
// Unlike //go:noinline, LLVM still DCEs dead calls to inferred-pure fns,
// so each result is pinned with black_box.

use std::hint::black_box;
use std::time::Instant;

#[inline(never)]
fn inner(x: i64) -> i64 {
    x + 1
}

#[inline(never)]
fn outer(x: i64) -> i64 {
    inner(x) * 3
}

fn main() {
    let iters: i64 = 10000000;
    let t0 = Instant::now();
    let mut acc: i64 = 0;
    for i in 0..iters {
        acc = black_box(outer(i));
    }
    let elapsed = t0.elapsed().as_nanos();
    println!("iters={}", iters);
    println!("acc={}", acc);
    println!("elapsed_ns={}", elapsed);
}
