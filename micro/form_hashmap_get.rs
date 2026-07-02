// Rust equivalent of form_hashmap_get.hl.
// Populate (outside timing) then N indexed lookups. Rust's `m[&k]`
// panics on absence — the analog of Hale's `m.get(k) or raise`; every
// key is present in this bench. Default SipHash-1-3 hasher (slower,
// DoS-resistant) vs Go's AES-based hash.

#![allow(dead_code)]

use std::collections::HashMap;
use std::time::Instant;

struct Entry {
    id: i64,
    v: i64,
}

fn main() {
    let n: i64 = 150000;
    let mut m: HashMap<i64, Entry> = HashMap::with_capacity(n as usize);
    for i in 0..n {
        m.insert(i, Entry { id: i, v: i + 1 });
    }

    let t0 = Instant::now();
    let mut acc: i64 = 0;
    for j in 0..n {
        acc += m[&j].v;
    }
    let elapsed = t0.elapsed().as_nanos();
    println!("n={}", n);
    println!("acc={}", acc);
    println!("elapsed_ns={}", elapsed);
}
