"""Python equivalent of str_concat_loop.hl — `+=` (CPython extends in place)."""

import time



def build(iters):
    # in a function: CPython extends a local string in place on `+=`;
    # at module level the global lookup defeats that and the loop is
    # quadratic (~35 s here)
    s = ""
    for _ in range(iters):
        s += "ab"
    return s


iters = 1000000
t0 = time.monotonic_ns()
s = build(iters)
elapsed = time.monotonic_ns() - t0
print(f"iters={iters}")
print(f"len={len(s)}")
print(f"elapsed_ns={elapsed}")
