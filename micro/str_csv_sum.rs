// Rust equivalent of str_csv_sum.hl — lines + split + parse.
use std::fmt::Write;
use std::time::Instant;

fn main() {
    let mut csv = String::new();
    for i in 0..1000 {
        writeln!(csv, "{},17,4,250,9,33,1024,{}", i, i % 7).unwrap();
    }
    let csv = std::hint::black_box(csv);
    let rounds = 100;
    let t0 = Instant::now();
    let mut total: i64 = 0;
    for _ in 0..rounds {
        for line in csv.lines() {
            total += line.split(',').map(|f| f.parse::<i64>().unwrap_or(0)).sum::<i64>();
        }
    }
    let elapsed = t0.elapsed().as_nanos();
    println!("rounds={}\ntotal={}\nelapsed_ns={}", rounds, total, elapsed);
}
