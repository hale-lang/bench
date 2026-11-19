// JS equivalent of str_csv_sum.hl — split + Number.
let csv = "";
for (let i = 0; i < 1000; i++) csv += `${i},17,4,250,9,33,1024,${i % 7}\n`;
const rounds = 100;
const t0 = process.hrtime.bigint();
let total = 0;
for (let r = 0; r < rounds; r++) {
    for (const line of csv.slice(0, -1).split("\n")) {
        total += line.split(",").map((f) => Number.parseInt(f, 10) || 0).reduce((a, b) => a + b, 0);
    }
}
const elapsed = process.hrtime.bigint() - t0;
console.log(`rounds=${rounds}`);
console.log(`total=${total}`);
console.log(`elapsed_ns=${elapsed}`);
