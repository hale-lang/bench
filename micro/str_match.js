// JS equivalent of str_match.hl — a string `switch` with 16 cases.
function arm(w) {
    switch (w) {
        case "alpha": return 1; case "bravo": return 2; case "charlie": return 3;
        case "delta": return 4; case "echo": return 5; case "foxtrot": return 6;
        case "golf": return 7; case "hotel": return 8; case "india": return 9;
        case "juliett": return 10; case "kilo": return 11; case "lima": return 12;
        case "mike": return 13; case "november": return 14; case "oscar": return 15;
        case "papa": return 16; default: return 0;
    }
}
const words = ["alpha", "bravo", "charlie", "delta", "echo", "foxtrot", "golf",
    "hotel", "india", "juliett", "kilo", "lima", "mike", "november", "oscar",
    "papa", "quebec"];
const iters = 2000000;
const t0 = process.hrtime.bigint();
let sum = 0;
for (let i = 0; i < iters; i++) sum += arm(words[i % 17]);
const elapsed = process.hrtime.bigint() - t0;
console.log(`iters=${iters}`);
console.log(`sum=${sum}`);
console.log(`elapsed_ns=${elapsed}`);
