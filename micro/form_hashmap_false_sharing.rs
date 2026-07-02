// Rust equivalent of form_hashmap_false_sharing.hl.
//
// Two threads hammer disjoint keys (even / odd ids) of a shared map.
// Cross-thread access via Mutex<HashMap> (the canonical Rust shape
// for a shared mutating map). std::thread threads are OS threads, so
// no LockOSThread analogue is needed — each writer natively owns its
// own OS thread, matching Hale's cooperative pools.
//
// Lock discipline matches Hale's `sync = serialized`: every mutate
// takes the per-map lock. Throughput is bounded by contention; this
// is the safe-but-slow baseline all three languages share.

#![allow(dead_code)]

use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Instant;

struct Counter {
    id: i64,
    value: i64,
}

struct Registry {
    entries: Mutex<HashMap<i64, Counter>>,
}

impl Registry {
    fn set(&self, c: Counter) {
        self.entries.lock().unwrap().insert(c.id, c);
    }

    fn len(&self) -> usize {
        self.entries.lock().unwrap().len()
    }
}

fn main() {
    let per_writer: i64 = 100000;
    let reg = Arc::new(Registry {
        entries: Mutex::new(HashMap::new()),
    });

    let t0 = Instant::now();

    // Thread A — even ids
    let reg_a = Arc::clone(&reg);
    let a = thread::spawn(move || {
        for i in 0..per_writer {
            reg_a.set(Counter { id: i * 2, value: i });
        }
    });

    // Thread B — odd ids
    let reg_b = Arc::clone(&reg);
    let b = thread::spawn(move || {
        for i in 0..per_writer {
            reg_b.set(Counter { id: i * 2 + 1, value: i });
        }
    });

    a.join().unwrap();
    b.join().unwrap();
    let elapsed = t0.elapsed().as_nanos();

    println!("per_writer={}", per_writer);
    println!("total={}", reg.len());
    println!("elapsed_ns={}", elapsed);
}
