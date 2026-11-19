// JS equivalent of bounded_records.hl — arrays of objects; the summary
// copies the tags array, as Hale's push copies the summary's tags.
function summaryOf(r) { return { id: r.id, tags: r.tags.slice() }; }
function round(k) {
    const rs = [];
    for (let j = 0; j < 32; j++) {
        const r = { id: `row-${k}-${j}`, tags: [] };
        r.tags.push({ name: "red" });
        r.tags.push({ name: `t${j}` });
        rs.push(r);
    }
    for (let j = 0; j < 32; j++) {
        const x = { ...rs[j] };
        x.id = x.id + "!";
        rs[j] = x;
    }
    const out = rs.map(summaryOf);
    let n = 0;
    for (const s of out) n += s.id.length + s.tags.length;
    return n;
}
const rounds = 20000;
const t0 = process.hrtime.bigint();
let total = 0;
for (let k = 0; k < rounds; k++) total += round(k);
const elapsed = process.hrtime.bigint() - t0;
console.log(`rounds=${rounds}`);
console.log(`total=${total}`);
console.log(`elapsed_ns=${elapsed}`);
