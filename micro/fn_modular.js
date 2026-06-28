// JS equivalent of fn_modular.hl — helper calls helper. V8 may inline
// the chain; that's the realistic JS comparison.

function inner(x) {
    return x + 1;
}

function outer(x) {
    return inner(x) * 3;
}

const iters = 10_000_000;
const t0 = process.hrtime.bigint();
let acc = 0;
for (let i = 0; i < iters; i++) {
    acc = outer(i);
}
const elapsed = process.hrtime.bigint() - t0;
console.log(`iters=${iters}`);
console.log(`acc=${acc}`);
console.log(`elapsed_ns=${elapsed}`);
