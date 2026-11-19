// Rust equivalent of ring_buffer_steady.hl — VecDeque with capacity 64.
use std::collections::VecDeque;
use std::time::Instant;

struct Sample { t: i64, v: i64, tag: String }

fn main() {
    let rounds: i64 = 2_000_000;
    let mut rb: VecDeque<Sample> = VecDeque::with_capacity(64);
    let t0 = Instant::now();
    for i in 0..32 {
        rb.push_back(Sample { t: i, v: i % 7, tag: format!("s{}", i % 10) });
    }
    let mut sum: i64 = 0;
    for k in 0..rounds {
        if rb.len() < 64 {
            rb.push_back(Sample { t: k, v: k % 7, tag: format!("s{}", k % 10) });
        }
        let got = rb.pop_front().unwrap_or(Sample { t: 0, v: 0, tag: String::new() });
        sum += got.v + got.tag.len() as i64;
    }
    let elapsed = t0.elapsed().as_nanos();
    println!("rounds={}\nsum={}\nelapsed_ns={}", rounds, sum, elapsed);
}
