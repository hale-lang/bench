// Rust equivalent of bounded_records.hl — Vec with capacity, owned
// Strings, `clone()` where Hale's push copies (the summary's tags).
use std::time::Instant;

#[derive(Clone, Default)]
struct Tag { name: String }
#[derive(Clone, Default)]
struct Row { id: String, tags: Vec<Tag> }
struct Sum { id: String, tags: Vec<Tag> }

fn summary_of(r: &Row) -> Sum { Sum { id: r.id.clone(), tags: r.tags.clone() } }

#[inline(never)]
fn round(k: usize) -> usize {
    let mut rs: Vec<Row> = Vec::with_capacity(64);
    for j in 0..32 {
        let mut r = Row { id: format!("row-{}-{}", k, j), tags: Vec::with_capacity(4) };
        r.tags.push(Tag { name: "red".to_string() });
        r.tags.push(Tag { name: format!("t{}", j) });
        rs.push(r);
    }
    for j in 0..32 {
        let x = &mut rs[j];
        x.id.push('!');
    }
    let out: Vec<Sum> = rs.iter().map(summary_of).collect();
    out.iter().map(|s| s.id.len() + s.tags.len()).sum()
}

fn main() {
    let rounds = 20000;
    let t0 = Instant::now();
    let mut total = 0;
    for k in 0..rounds {
        total += round(std::hint::black_box(k));
    }
    let elapsed = t0.elapsed().as_nanos();
    println!("rounds={}\ntotal={}\nelapsed_ns={}", rounds, total, elapsed);
}
