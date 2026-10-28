"""Python equivalent of method_loop_alloc.hl.

A method on a class loops 10M times, formatting the counter into a
fresh string each iteration and dropping it.
"""

import time


class Bench:
    def __init__(self, n):
        self.n = n

    def work(self):
        total = 0
        for i in range(self.n):
            s = str(i)
            total = total + len(s)
        return total


b = Bench(10000000)
t0 = time.monotonic_ns()
total = b.work()
elapsed = time.monotonic_ns() - t0
print(f"n={b.n}")
print(f"total={total}")
print(f"elapsed_ns={elapsed}")
