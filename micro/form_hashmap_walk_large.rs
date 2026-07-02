// Rust equivalent of form_hashmap_walk_large.hl.
//
// Pre-populate a map, then iterate — Rust's HashMap iterator is the
// natural analogue of Hale's key_at / entry_at sweep. Sum the values
// to defeat dead-code elimination. Iteration order is hash-table
// order in both languages (Rust's SipHash key is random per process;
// Hale is insertion-affected but deterministic per table state) —
// the comparison is throughput-per-entry, not order.

#![allow(dead_code)]

use std::collections::HashMap;
use std::time::Instant;

struct Entry {
    id: i64,
    val: i64,
}

fn main() {
    let n: i64 = 100000;
    let mut m: HashMap<i64, Entry> = HashMap::with_capacity(n as usize);
    for i in 0..n {
        m.insert(i, Entry { id: i, val: i * 3 });
    }

    let t0 = Instant::now();
    let mut sum: i64 = 0;
    for (k, e) in &m {
        sum += e.val + (k - k);
    }
    let elapsed = t0.elapsed().as_nanos();

    println!("n={}", n);
    println!("len={}", m.len());
    println!("sum={}", sum);
    println!("elapsed_ns={}", elapsed);
}
