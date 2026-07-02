// Rust equivalent of loop_overhead.hl.
// XOR accumulation defeats DCE without overflow concerns; pid-seeded
// bounds defeat constant folding. LLVM may vectorize the XOR loop
// where Go doesn't — this measures best-effort loop throughput per
// language, same as the .go.

use std::time::Instant;

fn main() {
    let pid = std::process::id() as i64;
    let iters: i64 = 100000000 + pid;
    let t0 = Instant::now();
    let mut acc: i64 = pid;
    for i in 0..iters {
        acc ^= i;
    }
    let elapsed = t0.elapsed().as_nanos();
    println!("iters={}", iters);
    println!("acc={}", acc);
    println!("elapsed_ns={}", elapsed);
}
