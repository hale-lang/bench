// JS equivalent of str_concat_loop.hl — `+=` (V8 builds a rope).
const iters = 1000000;
const t0 = process.hrtime.bigint();
let s = "";
for (let i = 0; i < iters; i++) s += "ab";
const n = s.length;
const elapsed = process.hrtime.bigint() - t0;
console.log(`iters=${iters}`);
console.log(`len=${n}`);
console.log(`elapsed_ns=${elapsed}`);
