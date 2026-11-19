// JS equivalent of ring_buffer_steady.hl — an array ring with head/size.
const CAP = 64;
const buf = new Array(CAP).fill(null);
let head = 0, size = 0;
function push(s) { if (size === CAP) return false; buf[(head + size) % CAP] = s; size++; return true; }
function pop() { if (size === 0) return null; const s = buf[head]; buf[head] = null; head = (head + 1) % CAP; size--; return s; }
const rounds = 2000000;
const t0 = process.hrtime.bigint();
for (let i = 0; i < 32; i++) push({ t: i, v: i % 7, tag: `s${i % 10}` });
let sum = 0;
for (let k = 0; k < rounds; k++) {
    push({ t: k, v: k % 7, tag: `s${k % 10}` });
    const got = pop() || { t: 0, v: 0, tag: "" };
    sum += got.v + got.tag.length;
}
const elapsed = process.hrtime.bigint() - t0;
console.log(`rounds=${rounds}`);
console.log(`sum=${sum}`);
console.log(`elapsed_ns=${elapsed}`);
