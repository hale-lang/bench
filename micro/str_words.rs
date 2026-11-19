// Rust equivalent of str_words.hl — split_whitespace.
use std::time::Instant;

fn main() {
    let text = "the quick brown fox jumps over a lazy dog and runs ".repeat(200);
    let text = std::hint::black_box(text);
    let rounds = 500;
    let t0 = Instant::now();
    let mut n = 0u64;
    for _ in 0..rounds {
        for w in text.split_whitespace() {
            if w.len() > 3 {
                n += 1;
            }
        }
    }
    let elapsed = t0.elapsed().as_nanos();
    println!("rounds={}\ncount={}\nelapsed_ns={}", rounds, n, elapsed);
}
