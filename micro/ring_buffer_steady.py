"""Python equivalent of ring_buffer_steady.hl — collections.deque."""

import time
from collections import deque


def run(rounds):
    rb = deque()
    for i in range(32):
        rb.append((i, i % 7, f"s{i % 10}"))
    total = 0
    for k in range(rounds):
        if len(rb) < 64:
            rb.append((k, k % 7, f"s{k % 10}"))
        _, v, tag = rb.popleft()
        total += v + len(tag)
    return total


rounds = 2000000
t0 = time.monotonic_ns()
total = run(rounds)
elapsed = time.monotonic_ns() - t0
print(f"rounds={rounds}")
print(f"sum={total}")
print(f"elapsed_ns={elapsed}")
