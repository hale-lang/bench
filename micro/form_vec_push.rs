// Rust equivalent of form_vec_push.hl.
// push to a Vec<i64> from cap=0; Rust's growth policy is doubling,
// same as Hale's @form(vec) (Go's append is similar but not identical
// above 1024 elements).

use std::time::Instant;

fn main() {
    let iters: i64 = 500000;
    let mut v: Vec<i64> = Vec::new();
    let t0 = Instant::now();
    for i in 0..iters {
        v.push(i);
    }
    let elapsed = t0.elapsed().as_nanos();
    println!("iters={}", iters);
    println!("len={}", v.len());
    println!("elapsed_ns={}", elapsed);
}
