//! wsload — fan-out from a Hale `ws::Hub` to N websocket clients,
//! standard library only (plus libc's clock_gettime, which std links).
//!
//! Opens `--clients` connections to `--addr`, upgrades each (RFC 6455,
//! `Authorization: Bearer bench`), subscribes each to `--topic`, and
//! waits for every `subscribed`. Then it writes `publish M` (or, with
//! `--pace`, `pace M`: one tick a millisecond) to `<--ctl>/cmd`, which
//! hub_serve.hl reads, and each client reads events
//! until the one with `"n":M` (the last; `drop_old` never sheds the
//! newest) or 10 s without a frame. Every event carries the hub's
//! publish time on CLOCK_MONOTONIC, so each delivery's latency is read
//! against the same clock here. Prints one JSON object: deliveries
//! expected and received, dropped (shed or lost: expected minus
//! received), the seconds from the command to the last delivery,
//! deliveries per second, and delivery-latency percentiles in µs.
//!
//! Build: `rustc -O --edition 2021 gates/wsload.rs -o <out>`

use std::io::{Read, Write};
use std::net::TcpStream;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Barrier};
use std::thread;
use std::time::{Duration, Instant};

#[repr(C)]
struct Timespec { sec: i64, nsec: i64 }
extern "C" { fn clock_gettime(clk: i32, ts: *mut Timespec) -> i32; }
fn mono_ns() -> i64 {
    let mut ts = Timespec { sec: 0, nsec: 0 };
    unsafe { clock_gettime(1, &mut ts) }; // CLOCK_MONOTONIC
    ts.sec * 1_000_000_000 + ts.nsec
}

fn frame(op: u8, payload: &[u8]) -> Vec<u8> {
    let key = [0x37u8, 0xfa, 0x21, 0x3d];
    let mut out = vec![0x80 | op];
    let n = payload.len();
    if n < 126 { out.push(0x80 | n as u8); } else { out.push(0x80 | 126); out.extend_from_slice(&(n as u16).to_be_bytes()); }
    out.extend_from_slice(&key);
    out.extend(payload.iter().enumerate().map(|(i, b)| b ^ key[i % 4]));
    out
}

/// One whole frame off the front of `buf`: (opcode, payload, bytes used).
fn parse(buf: &[u8]) -> Option<(u8, Vec<u8>, usize)> {
    if buf.len() < 2 { return None; }
    let op = buf[0] & 15;
    let mut n = (buf[1] & 127) as usize;
    let mut at = 2;
    if n == 126 { if buf.len() < 4 { return None; } n = u16::from_be_bytes([buf[2], buf[3]]) as usize; at = 4; }
    else if n == 127 { if buf.len() < 10 { return None; } n = u64::from_be_bytes(buf[2..10].try_into().unwrap()) as usize; at = 10; }
    if buf.len() < at + n { return None; }
    Some((op, buf[at..at + n].to_vec(), at + n))
}

fn field(s: &str, key: &str) -> Option<i64> {
    let i = s.find(key)? + key.len();
    let rest = &s[i..];
    let end = rest.find(|c: char| !(c.is_ascii_digit() || c == '-')).unwrap_or(rest.len());
    rest[..end].parse().ok()
}

fn main() {
    let a: Vec<String> = std::env::args().skip(1).collect();
    let get = |k: &str, d: &str| a.iter().position(|x| x == k).map(|i| a[i + 1].clone()).unwrap_or(d.to_string());
    let addr = get("--addr", "127.0.0.1:8796");
    let clients: usize = get("--clients", "16").parse().unwrap();
    let messages: i64 = get("--messages", "10000").parse().unwrap();
    let topic = get("--topic", "Ticks");
    let ctl = get("--ctl", "/tmp");
    let verb = if a.iter().any(|x| x == "--pace") { "pace" } else { "publish" };
    let ready = Arc::new(Barrier::new(clients + 1));
    let go = Arc::new(Barrier::new(clients + 1));
    let failed = Arc::new(AtomicUsize::new(0));
    let mut hs = Vec::new();
    for _ in 0..clients {
        let (addr, topic, ready, go, failed) = (addr.clone(), topic.clone(), ready.clone(), go.clone(), failed.clone());
        hs.push(thread::spawn(move || {
            let mut s = TcpStream::connect(&addr).expect("connect");
            s.set_nodelay(true).ok();
            let req = format!("GET / HTTP/1.1\r\nHost: hub\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\nAuthorization: Bearer bench\r\n\r\n");
            s.write_all(req.as_bytes()).unwrap();
            let mut buf = Vec::new();
            let mut chunk = vec![0u8; 1 << 16];
            s.set_read_timeout(Some(Duration::from_secs(10))).ok();
            loop {
                if let Some(p) = buf.windows(4).position(|w| w == b"\r\n\r\n") {
                    let head = String::from_utf8_lossy(&buf[..p]).to_string();
                    if !head.starts_with("HTTP/1.1 101") { failed.fetch_add(1, Ordering::Relaxed); }
                    buf.drain(..p + 4);
                    break;
                }
                let n = s.read(&mut chunk).unwrap_or(0);
                if n == 0 { panic!("closed during the handshake"); }
                buf.extend_from_slice(&chunk[..n]);
            }
            s.write_all(&frame(1, format!("{{\"type\":\"subscribe\",\"topic\":\"{topic}\"}}").as_bytes())).unwrap();
            // until `subscribed`
            loop {
                if let Some((_, p, used)) = parse(&buf) {
                    buf.drain(..used);
                    if String::from_utf8_lossy(&p).contains("\"subscribed\"") { break; }
                    continue;
                }
                let n = s.read(&mut chunk).unwrap_or(0);
                if n == 0 { panic!("closed before subscribed"); }
                buf.extend_from_slice(&chunk[..n]);
            }
            ready.wait();
            go.wait();
            let (mut got, mut last_at) = (0i64, Instant::now());
            let mut lat: Vec<u32> = Vec::with_capacity(messages as usize);
            'read: loop {
                while let Some((op, p, used)) = parse(&buf) {
                    buf.drain(..used);
                    if op != 1 { continue; }
                    let now = mono_ns();
                    let t = String::from_utf8_lossy(&p);
                    if !t.contains("\"event\"") { continue; }
                    got += 1;
                    last_at = Instant::now();
                    if let Some(at) = field(&t, "\"at\":") { lat.push(((now - at).max(0) / 1000) as u32); }
                    if field(&t, "\"n\":") == Some(messages) { break 'read; }
                }
                match s.read(&mut chunk) {
                    Ok(0) | Err(_) => break,
                    Ok(n) => buf.extend_from_slice(&chunk[..n]),
                }
            }
            (got, last_at, lat)
        }));
    }
    ready.wait();
    let t0 = Instant::now();
    std::fs::write(format!("{ctl}/cmd"), format!("{verb} {messages}\n")).expect("write the command");
    go.wait();
    let (mut got, mut last, mut lat) = (0i64, t0, Vec::new());
    for h in hs {
        let (g, l, mut v) = h.join().unwrap();
        got += g;
        if l > last { last = l; }
        lat.append(&mut v);
    }
    lat.sort_unstable();
    let pct = |p: f64| -> u32 { if lat.is_empty() { 0 } else { lat[((lat.len() as f64 * p).ceil() as usize).clamp(1, lat.len()) - 1] } };
    let secs = (last - t0).as_secs_f64();
    let expected = messages * clients as i64;
    println!(
        "{{\"mode\":\"{}\",\"clients\":{},\"messages\":{},\"expected\":{},\"delivered\":{},\"dropped\":{},\"refused_upgrades\":{},\"seconds\":{:.4},\"deliveries_per_s\":{:.0},\"p50_us\":{},\"p99_us\":{},\"max_us\":{}}}",
        verb, clients, messages, expected, got, expected - got, failed.load(Ordering::Relaxed), secs,
        got as f64 / secs.max(1e-9), pct(0.5), pct(0.99), lat.last().copied().unwrap_or(0)
    );
}
