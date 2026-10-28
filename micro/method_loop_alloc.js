// JS equivalent of method_loop_alloc.hl.
// A method on a class loops 10M times, formatting the counter into a
// fresh string each iteration and dropping it.

class Bench {
    constructor(n) {
        this.n = n;
    }

    work() {
        let total = 0;
        for (let i = 0; i < this.n; i++) {
            const s = String(i);
            total = total + s.length;
        }
        return total;
    }
}

const b = new Bench(10000000);
const t0 = process.hrtime.bigint();
const total = b.work();
const elapsed = process.hrtime.bigint() - t0;
console.log(`n=${b.n}`);
console.log(`total=${total}`);
console.log(`elapsed_ns=${elapsed}`);
