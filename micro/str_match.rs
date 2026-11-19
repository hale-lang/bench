// Rust equivalent of str_match.hl — `match` on &str with 16 arms.
use std::time::Instant;

#[inline(never)]
fn arm(w: &str) -> i64 {
    match w {
        "alpha" => 1, "bravo" => 2, "charlie" => 3, "delta" => 4,
        "echo" => 5, "foxtrot" => 6, "golf" => 7, "hotel" => 8,
        "india" => 9, "juliett" => 10, "kilo" => 11, "lima" => 12,
        "mike" => 13, "november" => 14, "oscar" => 15, "papa" => 16,
        _ => 0,
    }
}

fn main() {
    let words = std::hint::black_box(["alpha", "bravo", "charlie", "delta", "echo", "foxtrot",
        "golf", "hotel", "india", "juliett", "kilo", "lima", "mike",
        "november", "oscar", "papa", "quebec"]);
    let iters = 2_000_000;
    let t0 = Instant::now();
    let mut sum = 0i64;
    for i in 0..iters {
        sum += arm(words[i % 17]);
    }
    let elapsed = t0.elapsed().as_nanos();
    println!("iters={}\nsum={}\nelapsed_ns={}", iters, sum, elapsed);
}
