// Rust equivalent of str_concat_loop.hl — String::push_str.
use std::time::Instant;

fn main() {
    let iters = 1_000_000;
    let t0 = Instant::now();
    let mut s = String::new();
    for _ in 0..iters {
        s.push_str(std::hint::black_box("ab"));
    }
    let elapsed = t0.elapsed().as_nanos();
    println!("iters={}\nlen={}\nelapsed_ns={}", iters, s.len(), elapsed);
}
