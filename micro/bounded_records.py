"""Python equivalent of bounded_records.hl — lists of dicts; the summary
copies the tags list, as Hale's push copies the summary's tags."""

import time


def summary_of(r):
    return {"id": r["id"], "tags": list(r["tags"])}


def round_(k):
    rs = []
    for j in range(32):
        r = {"id": f"row-{k}-{j}", "tags": []}
        r["tags"].append({"name": "red"})
        r["tags"].append({"name": f"t{j}"})
        rs.append(r)
    for j in range(32):
        x = dict(rs[j])
        x["id"] = x["id"] + "!"
        rs[j] = x
    out = [summary_of(r) for r in rs]
    return sum(len(s["id"]) + len(s["tags"]) for s in out)


rounds = 20000
t0 = time.monotonic_ns()
total = 0
for k in range(rounds):
    total += round_(k)
elapsed = time.monotonic_ns() - t0
print(f"rounds={rounds}")
print(f"total={total}")
print(f"elapsed_ns={elapsed}")
