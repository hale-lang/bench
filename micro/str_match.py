"""Python equivalent of str_match.hl — a `match` with 16 literal cases."""

import time


def arm(w):
    match w:
        case "alpha": return 1
        case "bravo": return 2
        case "charlie": return 3
        case "delta": return 4
        case "echo": return 5
        case "foxtrot": return 6
        case "golf": return 7
        case "hotel": return 8
        case "india": return 9
        case "juliett": return 10
        case "kilo": return 11
        case "lima": return 12
        case "mike": return 13
        case "november": return 14
        case "oscar": return 15
        case "papa": return 16
        case _: return 0


words = ["alpha", "bravo", "charlie", "delta", "echo", "foxtrot", "golf",
         "hotel", "india", "juliett", "kilo", "lima", "mike", "november",
         "oscar", "papa", "quebec"]
iters = 2000000
t0 = time.monotonic_ns()
total = 0
for i in range(iters):
    total += arm(words[i % 17])
elapsed = time.monotonic_ns() - t0
print(f"iters={iters}")
print(f"sum={total}")
print(f"elapsed_ns={elapsed}")
