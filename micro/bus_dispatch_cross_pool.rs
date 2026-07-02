// Rust equivalent of bus_dispatch_cross_pool.hl.
//
// Two threads: main publishes, a worker subscribes. Cross-thread
// delivery via a bounded mpsc::sync_channel (cap 64, mirroring
// Hale's bounded io pool queue depth — a rendezvous channel would
// pin publish to drain rate per message; a huge buffer would let the
// publisher dump and run, defeating the purpose).
//
// std::thread threads are OS threads, so no LockOSThread analogue is
// needed — the subscriber natively owns a distinct OS thread, the
// direct equivalent of "cooperative(pool = io) has its own OS thread".

#![allow(dead_code)]

use std::sync::mpsc;
use std::thread;
use std::time::Instant;

struct Tick {
    n: i64,
}

fn main() {
    let iters: i64 = 100000;
    let (tx, rx) = mpsc::sync_channel::<Tick>(64);

    let sub = thread::spawn(move || {
        let mut count: i64 = 0;
        for _t in rx {
            count += 1;
        }
        count
    });

    let t0 = Instant::now();
    for i in 0..iters {
        tx.send(Tick { n: i }).unwrap();
    }
    let elapsed = t0.elapsed().as_nanos();
    drop(tx);
    let count = sub.join().unwrap();

    println!("iters={}", iters);
    println!("count={}", count);
    println!("elapsed_ns={}", elapsed);
}
