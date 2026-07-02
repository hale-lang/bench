// Rust equivalent of fn_scratch_work.hl.
// 100 fn calls × 1000-element local Vec each. Vec::new() from cap=0
// mirrors Go's make([]int, 0) + append growth.

use std::time::Instant;

#[inline(never)]
fn do_work(n: i64) -> i64 {
    let mut v: Vec<i64> = Vec::new();
    for i in 0..n {
        v.push(i);
    }
    let mut sum: i64 = 0;
    for j in 0..n as usize {
        sum += v[j];
    }
    sum
}

fn main() {
    let calls: i64 = 100;
    let per_call: i64 = 1000;
    let t0 = Instant::now();
    let mut total: i64 = 0;
    for _c in 0..calls {
        total += do_work(per_call);
    }
    let elapsed = t0.elapsed().as_nanos();
    println!("calls={}", calls);
    println!("per_call={}", per_call);
    println!("total={}", total);
    println!("elapsed_ns={}", elapsed);
}
