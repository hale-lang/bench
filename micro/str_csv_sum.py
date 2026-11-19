"""Python equivalent of str_csv_sum.hl — splitlines + split + int."""

import time

csv = "".join(f"{i},17,4,250,9,33,1024,{i % 7}\n" for i in range(1000))
rounds = 100
t0 = time.monotonic_ns()
total = 0
for _ in range(rounds):
    for line in csv.splitlines():
        total += sum(int(f) for f in line.split(","))
elapsed = time.monotonic_ns() - t0
print(f"rounds={rounds}")
print(f"total={total}")
print(f"elapsed_ns={elapsed}")
