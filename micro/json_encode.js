// JS equivalent of json_encode.hl — JSON.stringify.
const iters = 200000;
const t0 = process.hrtime.bigint();
let total = 0;
for (let i = 0; i < iters; i++) {
    const q = { sym: "BTCUSD", bid: 50000, ask: 50010, bidsz: 12, asksz: 8, ts: 1700000000000, seq: i };
    total = total + JSON.stringify(q).length;
}
const elapsed = process.hrtime.bigint() - t0;
console.log(`iters=${iters}`);
console.log(`total=${total}`);
console.log(`elapsed_ns=${elapsed}`);
