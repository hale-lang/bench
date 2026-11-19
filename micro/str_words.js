// JS equivalent of str_words.hl — split on whitespace runs.
const text = "the quick brown fox jumps over a lazy dog and runs ".repeat(200);
const rounds = 500;
const t0 = process.hrtime.bigint();
let n = 0;
for (let r = 0; r < rounds; r++) {
    for (const w of text.split(/\s+/)) {
        if (w.length > 3) n++;
    }
}
const elapsed = process.hrtime.bigint() - t0;
console.log(`rounds=${rounds}`);
console.log(`count=${n}`);
console.log(`elapsed_ns=${elapsed}`);
