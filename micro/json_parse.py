"""Python equivalent of json_parse.hl — json.loads."""

import json
import time

body = '{"sym": "BTCUSD", "bid": 50000, "ask": 50010, "bidsz": 12, "asksz": 8, "ts": 1700000000000, "seq": 42}'
iters = 200000
t0 = time.monotonic_ns()
total = 0
for _ in range(iters):
    q = json.loads(body)
    total = total + q["bid"] + q["ask"]
elapsed = time.monotonic_ns() - t0
print(f"iters={iters}")
print(f"total={total}")
print(f"elapsed_ns={elapsed}")
