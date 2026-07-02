// Rust equivalent of form_hashmap_set.hl.
// N inserts into a HashMap<i64, Entry>. Rust's std map is SwissTable
// (SIMD open addressing) with SipHash-1-3 keys — same big-O as Hale's
// open-addressing implementation, different probing and a slower
// (DoS-resistant) default hasher than Go's.

#![allow(dead_code)]

use std::collections::HashMap;
use std::time::Instant;

struct Entry {
    id: i64,
    v: i64,
}

fn main() {
    let n: i64 = 1000000;
    let mut m: HashMap<i64, Entry> = HashMap::new();
    let t0 = Instant::now();
    for i in 0..n {
        m.insert(i, Entry { id: i, v: i + 1 });
    }
    let elapsed = t0.elapsed().as_nanos();
    println!("n={}", n);
    println!("len={}", m.len());
    println!("elapsed_ns={}", elapsed);
}
