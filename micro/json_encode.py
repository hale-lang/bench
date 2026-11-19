"""Python equivalent of json_encode.hl — json.dumps."""

import json
import time

iters = 200000
t0 = time.monotonic_ns()
total = 0
for i in range(iters):
    q = {"sym": "BTCUSD", "bid": 50000, "ask": 50010, "bidsz": 12, "asksz": 8, "ts": 1700000000000, "seq": i}
    total = total + len(json.dumps(q, separators=(",", ":")))
elapsed = time.monotonic_ns() - t0
print(f"iters={iters}")
print(f"total={total}")
print(f"elapsed_ns={elapsed}")
