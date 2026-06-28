"""Python equivalent of fn_modular.hl — helper calls helper in a tight
loop. Two frame allocations per iteration."""

import time


def inner(x):
    return x + 1


def outer(x):
    return inner(x) * 3


iters = 10_000_000
t0 = time.monotonic_ns()
acc = 0
for i in range(iters):
    acc = outer(i)
elapsed = time.monotonic_ns() - t0
print(f"iters={iters}")
print(f"acc={acc}")
print(f"elapsed_ns={elapsed}")
