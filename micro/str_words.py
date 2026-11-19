"""Python equivalent of str_words.hl — str.split()."""

import time

text = "the quick brown fox jumps over a lazy dog and runs " * 200
rounds = 500
t0 = time.monotonic_ns()
n = 0
for _ in range(rounds):
    for w in text.split():
        if len(w) > 3:
            n += 1
elapsed = time.monotonic_ns() - t0
print(f"rounds={rounds}")
print(f"count={n}")
print(f"elapsed_ns={elapsed}")
