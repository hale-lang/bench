// Rust equivalent of form_vec_get.hl.
// Populate (outside timing) then time bounds-checked indexed reads.
// Rust's v[j] is bounds-checked like Go's — closest analog to Hale's
// `get(i) or raise` — though LLVM may hoist/elide the check.

use std::time::Instant;

fn main() {
    let iters: i64 = 200000;
    let mut v: Vec<i64> = Vec::with_capacity(iters as usize);
    for i in 0..iters {
        v.push(i);
    }

    let t0 = Instant::now();
    let mut acc: i64 = 0;
    for j in 0..iters as usize {
        acc ^= v[j];
    }
    let elapsed = t0.elapsed().as_nanos();

    println!("iters={}", iters);
    println!("acc={}", acc);
    println!("elapsed_ns={}", elapsed);
}
