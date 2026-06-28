"""Python equivalent of fn_call.hl — free fn with a minimal body in a
tight loop. Python's per-call frame allocation dominates."""

import time


def step(x):
    return x * 2 + 1


iters = 10_000_000
t0 = time.monotonic_ns()
acc = 0
for i in range(iters):
    acc = step(i)
elapsed = time.monotonic_ns() - t0
print(f"iters={iters}")
print(f"acc={acc}")
print(f"elapsed_ns={elapsed}")
