// Rust equivalent of json_parse.hl — schema-specialized JSON parse
// throughput. Rust's std has no JSON, so this is a minimal
// hand-rolled single-pass parser for the fixed quote schema — closer
// in spirit to Hale's generated from_json (Tier 2, schema-
// specialized) than to Go's reflective encoding/json. Caveat: no
// string-escape handling (the input has none), so it undercuts a
// general-purpose parser.

#![allow(dead_code)]

use std::time::Instant;

struct Quote {
    sym: String,
    bid: i64,
    ask: i64,
    bidsz: i64,
    asksz: i64,
    ts: i64,
    seq: i64,
}

struct Cur<'a> {
    b: &'a [u8],
    i: usize,
}

impl<'a> Cur<'a> {
    fn ws(&mut self) {
        while self.i < self.b.len() && self.b[self.i].is_ascii_whitespace() {
            self.i += 1;
        }
    }

    fn eat(&mut self, c: u8) -> Option<()> {
        self.ws();
        if self.i < self.b.len() && self.b[self.i] == c {
            self.i += 1;
            Some(())
        } else {
            None
        }
    }

    fn peek(&mut self) -> Option<u8> {
        self.ws();
        self.b.get(self.i).copied()
    }

    fn string(&mut self) -> Option<String> {
        self.eat(b'"')?;
        let start = self.i;
        while *self.b.get(self.i)? != b'"' {
            self.i += 1;
        }
        let s = String::from_utf8(self.b[start..self.i].to_vec()).ok()?;
        self.i += 1;
        Some(s)
    }

    fn int(&mut self) -> Option<i64> {
        self.ws();
        let mut neg = false;
        if self.peek()? == b'-' {
            neg = true;
            self.i += 1;
        }
        let start = self.i;
        let mut v: i64 = 0;
        while let Some(&c) = self.b.get(self.i) {
            if !c.is_ascii_digit() {
                break;
            }
            v = v * 10 + (c - b'0') as i64;
            self.i += 1;
        }
        if self.i == start {
            return None;
        }
        Some(if neg { -v } else { v })
    }
}

fn parse_quote(body: &[u8]) -> Option<Quote> {
    let mut c = Cur { b: body, i: 0 };
    let mut q = Quote {
        sym: String::new(),
        bid: 0,
        ask: 0,
        bidsz: 0,
        asksz: 0,
        ts: 0,
        seq: 0,
    };
    c.eat(b'{')?;
    loop {
        let key = c.string()?;
        c.eat(b':')?;
        match key.as_str() {
            "sym" => q.sym = c.string()?,
            "bid" => q.bid = c.int()?,
            "ask" => q.ask = c.int()?,
            "bidsz" => q.bidsz = c.int()?,
            "asksz" => q.asksz = c.int()?,
            "ts" => q.ts = c.int()?,
            "seq" => q.seq = c.int()?,
            _ => return None,
        }
        if c.peek()? == b',' {
            c.i += 1;
        } else {
            break;
        }
    }
    c.eat(b'}')?;
    Some(q)
}

fn main() {
    let body = br#"{"sym": "BTCUSD", "bid": 50000, "ask": 50010, "bidsz": 12, "asksz": 8, "ts": 1700000000000, "seq": 42}"#;
    let iters: i64 = 200000;
    let t0 = Instant::now();
    let mut total: i64 = 0;
    for _i in 0..iters {
        let q = parse_quote(body).unwrap();
        total += q.bid + q.ask;
    }
    let elapsed = t0.elapsed().as_nanos();
    println!("iters={}", iters);
    println!("total={}", total);
    println!("elapsed_ns={}", elapsed);
}
