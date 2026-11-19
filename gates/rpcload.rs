//! rpcload — a closed-loop load generator for a Hale `unix::Rpc` exposure,
//! standard library only.
//!
//! Each of `--conns` threads holds one connection to the socket at
//! `--path` and sends `{"call":"Echo::on_ping","payload":{"n":N},"id":"c"}`
//! lines back to back: the next call goes out when the last reply line is
//! read. A reply without `"ok":true` is an `error`; a connection that
//! fails before its reply is complete is a `dropped` call, counted when
//! it fails inside the measured window, then sent again on a new
//! connection. The first `--warmup` seconds are not recorded. Prints one
//! JSON object: calls, errors, dropped, calls per second and latency
//! percentiles in microseconds.
//!
//! Build: `rustc -O --edition 2021 gates/rpcload.rs -o <out>`
//! Run:   `<out> --path /tmp/x.sock --conns 16 --duration 10 --warmup 2`

use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::UnixStream;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::{Duration, Instant};

fn connect(path: &str) -> (UnixStream, BufReader<UnixStream>) {
    loop {
        if let Ok(s) = UnixStream::connect(path) {
            let r = BufReader::new(s.try_clone().expect("clone"));
            return (s, r);
        }
        thread::sleep(Duration::from_millis(1));
    }
}

fn main() {
    let a: Vec<String> = std::env::args().skip(1).collect();
    let get = |k: &str, d: &str| a.iter().position(|x| x == k).map(|i| a[i + 1].clone()).unwrap_or(d.to_string());
    let path = get("--path", "/tmp/hale-bench-rpc.sock");
    let conns: usize = get("--conns", "1").parse().unwrap();
    let duration: f64 = get("--duration", "10").parse().unwrap();
    let warmup: f64 = get("--warmup", "2").parse().unwrap();
    let stop = Arc::new(AtomicBool::new(false));
    let start = Instant::now();
    let warm = Duration::from_secs_f64(warmup);
    let end = Duration::from_secs_f64(warmup + duration);
    let mut handles = Vec::new();
    for c in 0..conns {
        let (path, stop) = (path.clone(), stop.clone());
        handles.push(thread::spawn(move || {
            let mut lat: Vec<u32> = Vec::with_capacity(1 << 20);
            let (mut errors, mut dropped) = (0u64, 0u64);
            let (mut w, mut r) = connect(&path);
            let mut line = String::new();
            let mut n: u64 = (c as u64) << 32;
            while !stop.load(Ordering::Relaxed) {
                let t = Instant::now();
                let msg = format!("{{\"call\":\"Echo::on_ping\",\"payload\":{{\"n\":{n}}},\"id\":\"c\"}}\n");
                n += 1;
                let ok = loop {
                    line.clear();
                    if w.write_all(msg.as_bytes()).is_ok() {
                        if let Ok(k) = r.read_line(&mut line) {
                            if k > 0 && line.ends_with('\n') {
                                break line.contains("\"ok\":true");
                            }
                        }
                    }
                    let at = start.elapsed();
                    if at >= warm && at < end {
                        dropped += 1;
                    }
                    let (w2, r2) = connect(&path);
                    w = w2;
                    r = r2;
                    if stop.load(Ordering::Relaxed) {
                        break false;
                    }
                };
                let since = start.elapsed();
                if since >= warm && since < end {
                    if ok {
                        lat.push(t.elapsed().as_micros().min(u32::MAX as u128) as u32);
                    } else {
                        errors += 1;
                    }
                }
            }
            (lat, errors, dropped)
        }));
    }
    thread::sleep(end);
    stop.store(true, Ordering::Relaxed);
    let (mut all, mut errors, mut dropped) = (Vec::new(), 0, 0);
    for h in handles {
        let (l, e, d) = h.join().unwrap();
        all.extend(l);
        errors += e;
        dropped += d;
    }
    all.sort_unstable();
    let pct = |p: f64| -> u32 {
        if all.is_empty() {
            return 0;
        }
        all[((all.len() as f64 * p).ceil() as usize).clamp(1, all.len()) - 1]
    };
    println!(
        "{{\"conns\":{},\"seconds\":{},\"requests\":{},\"errors\":{},\"dropped\":{},\"rps\":{:.0},\"p50_us\":{},\"p90_us\":{},\"p99_us\":{},\"p999_us\":{},\"max_us\":{}}}",
        conns, duration, all.len(), errors, dropped, all.len() as f64 / duration,
        pct(0.50), pct(0.90), pct(0.99), pct(0.999), all.last().copied().unwrap_or(0)
    );
}
