// Rust equivalent of vec_amortized.hl.
// Build + consume in a single timed region. Rust frees at scope end
// rather than via GC, so the "cleanup" the .go amortizes into the GC
// happens outside the timed region here — same as Hale's arena.

use std::time::Instant;

fn main() {
    let n: i64 = 200000;
    let t0 = Instant::now();

    let mut v: Vec<i64> = Vec::new();
    for i in 0..n {
        v.push(i);
    }
    let mut sum: i64 = 0;
    for j in 0..n as usize {
        sum += v[j];
    }

    let elapsed = t0.elapsed().as_nanos();
    println!("n={}", n);
    println!("sum={}", sum);
    println!("elapsed_ns={}", elapsed);
}
