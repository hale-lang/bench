// Rust equivalent of pipeline_3stage.hl.
// Three components connected by a subject-keyed router map — the
// same shape as bus_dispatch.rs, just with two hops. Each publish is
// a map lookup + indirect (dyn Fn) call (no queue, no memcpy like
// Hale's bus pays). Cell counters stand in for Go's pointer-receiver
// mutation across the shared router graph.

use std::cell::Cell;
use std::collections::HashMap;
use std::time::Instant;

struct Event {
    value: i64,
}

struct Filtered {
    value: i64,
}

struct Sink {
    count: Cell<i64>,
    sum: Cell<i64>,
}

impl Sink {
    #[inline(never)]
    fn on_filtered(&self, f: Filtered) {
        self.count.set(self.count.get() + 1);
        self.sum.set(self.sum.get() + f.value);
    }
}

struct Filter<'a> {
    passed: Cell<i64>,
    router: HashMap<&'static str, Box<dyn Fn(Filtered) + 'a>>,
}

impl<'a> Filter<'a> {
    #[inline(never)]
    fn on_event(&self, e: Event) {
        if e.value % 2 == 0 {
            self.passed.set(self.passed.get() + 1);
            self.router["filtered"](Filtered { value: e.value });
        }
    }
}

struct Source<'a> {
    count: i64,
    router: HashMap<&'static str, Box<dyn Fn(Event) + 'a>>,
}

impl<'a> Source<'a> {
    fn run(&self) {
        let emit = &self.router["event"];
        for i in 0..self.count {
            emit(Event { value: i });
        }
    }
}

fn main() {
    let n: i64 = 50000;
    let sink = Sink {
        count: Cell::new(0),
        sum: Cell::new(0),
    };
    let mut filter_router: HashMap<&'static str, Box<dyn Fn(Filtered) + '_>> = HashMap::new();
    filter_router.insert("filtered", Box::new(|f| sink.on_filtered(f)));
    let filter = Filter {
        passed: Cell::new(0),
        router: filter_router,
    };
    let mut source_router: HashMap<&'static str, Box<dyn Fn(Event) + '_>> = HashMap::new();
    source_router.insert("event", Box::new(|e| filter.on_event(e)));
    let source = Source {
        count: n,
        router: source_router,
    };

    let t0 = Instant::now();
    source.run();
    let elapsed = t0.elapsed().as_nanos();

    println!("n={}", n);
    println!("filter_passed={}", filter.passed.get());
    println!("sink_count={}", sink.count.get());
    println!("sink_sum={}", sink.sum.get());
    println!("elapsed_ns={}", elapsed);
}
