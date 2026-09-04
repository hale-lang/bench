#!/usr/bin/env bash
# rebaseline.sh — rebuild baselines.json from SEVERAL independent runs.
#
# Why this is not `run.sh --update-baselines` (which now refuses):
#
# A tolerance band is a claim about what the harness can resolve, and
# the thing that limits that is NOT the jitter between iterations
# inside one run. Measured on 22 benches over three sweeps of one
# byte-identical binary:
#
#   within-run median SE   0.3% – 3.5%   (median 1.3%)
#   run-to-run drift       0.0% – 25.5%  (median 4.9%, p90 10.6%)
#
# Drift dominates by 3-5x. It is machine state — thermal, page cache,
# whatever else was running — and a single run cannot see any of it,
# because every sample shares that state. Bands built from one run
# fire on the next run of the same binary: the first attempt at this
# produced THREE false regressions (form_vec_push +21.6%,
# pipeline_3stage +9.6%, bus_dispatch_heap_payload +7.2%) against the
# compiler they were baselined on.
#
# So: run the suite N times, take the median of each bench's medians,
# and record BOTH noise terms. `run.sh` combines them into a band.
#
# Usage:
#   ./rebaseline.sh                 # 5 runs x 21 iters, hale only
#   ./rebaseline.sh 5 31            # 5 runs x 31 iters
#
# Cost: N full sweeps. Baselining is rare; being wrong about it is
# expensive for a long time (hale-lang/hale#522 hid for five
# releases behind a band nobody had measured).
set -euo pipefail
cd "$(dirname "$0")"

RUNS=${1:-5}
ITERS=${2:-21}

if [ "$RUNS" -lt 2 ]; then
    echo "rebaseline: need at least 2 runs to see drift at all" >&2
    exit 2
fi

# Same resolution order as run.sh, so the stamp names the binary
# that was actually measured.
if [[ -n "${HALE_BIN:-}" ]]; then HALE="$HALE_BIN"
elif [[ -x "../hale/target/release/hale" ]]; then HALE="../hale/target/release/hale"
else HALE="$(command -v hale)"; fi
"$HALE" --version 2>/dev/null | awk '{print $2}' > /tmp/.rebaseline_version

echo "rebaseline: $RUNS runs x $ITERS iters against $("$HALE" --version)"
reports=()
for i in $(seq 1 "$RUNS"); do
    echo ""
    echo "--- run $i/$RUNS ---"
    # `|| true`: these runs MEASURE, they do not judge. run.sh exits
    # non-zero when a bench trips the OLD band, which is expected
    # here — re-baselining is usually why you are running this — and
    # under `set -e` that would abort the sweep half-collected.
    HALE_REBASELINE=1 ./run.sh --no-comparative --iters="$ITERS" \
        >/dev/null || true
    # No `ls | head`: head exits after one line, ls dies of SIGPIPE,
    # and `set -o pipefail` turns that into a 141 that kills the
    # sweep after all the measuring is done and before any of it is
    # used.
    mapfile -t _all < <(ls -t results/run-*.json)
    reports+=("${_all[0]}")
    echo "    $(basename "${_all[0]}")"
done

echo ""
echo "computing baselines from ${#reports[@]} runs"
python3 - "${reports[@]}" <<'PY'
import json, sys, statistics as st, datetime

# Control-chart constants: E[range of n samples] = d2(n) * sigma.
_D2 = {2: 1.128, 3: 1.693, 4: 2.059, 5: 2.326, 6: 2.534, 7: 2.704,
       8: 2.847, 9: 2.970, 10: 3.078, 11: 3.173, 12: 3.258,
       13: 3.336, 14: 3.407, 15: 3.472}

def d2(n):
    if n in _D2:
        return _D2[n]
    return _D2[max(_D2)] if n > max(_D2) else _D2[2]

reports = [json.load(open(p)) for p in sys.argv[1:]]

# name -> [median per run], and the within-run SEs we already computed
per_run, ses, kinds, rss = {}, {}, {}, {}
seen, unusable = set(), {}
for r in reports:
    for b in r["benches"]:
        seen.add(b["name"])
        # Accept "regression" and "inconclusive" — those are verdicts
        # against the OLD band, and re-recording them is the entire
        # point of re-baselining. Filtering on status == "ok" silently
        # dropped 7 of 22 benches on the first attempt, which would
        # have left every one of them ungated (no `noise` key means
        # run.sh falls back to the wide default).
        #
        # "fail" is different: the binary did not run, so there is no
        # number to record.
        if b["status"] == "fail":
            unusable.setdefault(b["name"], set()).add("did not run")
            continue
        per_run.setdefault(b["name"], []).append(b["elapsed_ns_median"])
        ses.setdefault(b["name"], []).append(b.get("elapsed_median_se", 0.0))
        kinds[b["name"]] = b["kind"]
        rss.setdefault(b["name"], []).append(b["maxrss_kb_median"])

# Keep any explicit override a human wrote down.
try:
    prev = json.load(open("baselines.json")).get("benches", {})
except Exception:
    prev = {}

benches = {}
for name, meds in sorted(per_run.items()):
    if len(meds) < len(reports):
        unusable.setdefault(name, set()).add(
            f"only {len(meds)}/{len(reports)} runs")
        continue
    entry = {
        "kind": kinds[name],
        "elapsed_ns": int(st.median(meds)),
        "maxrss_kb": int(st.median(rss[name])),
        # Within-run sampling noise: how well ONE run pins its median.
        "noise": round(st.median(ses[name]), 4),
        # Between-run drift, as an estimated SIGMA rather than the
        # raw observed range.
        #
        # The range of N samples underestimates spread badly at
        # small N — E[range] = d2(N) * sigma, and d2(3) is only
        # 1.69. Recording the raw range from 3 runs produced bands
        # up to 4x too tight on the noisiest benches
        # (bus_dispatch_heap_payload got 6% for a bench that moves
        # 21% run to run), and they fired on the next sweep of the
        # same binary. Dividing by d2(N) makes the estimate
        # unbiased at any N; more runs then buy PRECISION in the
        # estimate rather than correcting a systematic error.
        "drift_sigma": round(
            ((max(meds) - min(meds)) / min(meds)) / d2(len(meds)), 4),
        "drift_range": round((max(meds) - min(meds)) / min(meds), 4),
        "runs": len(meds),
    }
    if "tolerance_override" in prev.get(name, {}):
        entry["tolerance_override"] = prev[name]["tolerance_override"]
    benches[name] = entry

ver = open("/tmp/.rebaseline_version").read().strip() or "unknown"
out = {
    "updated_at": datetime.datetime.now(datetime.timezone.utc)
                    .strftime("%Y-%m-%dT%H:%M:%SZ"),
    "hale_version": ver,
    "runs": len(reports),
    "iters": reports[0].get("iters"),
    "benches": benches,
}
json.dump(out, open("baselines.json", "w"), indent=2)
open("baselines.json", "a").write("\n")

def band(e, k=4, lo=0.05, hi=0.35):
    return min(hi, max(lo, e["noise"] * k, e["drift_sigma"] * k))

print(f"\n{'bench':30}{'median':>11}{'noise':>8}{'drift s':>9}{'band':>7}")
for n, e in sorted(benches.items(), key=lambda kv: band(kv[1])):
    print(f"{n:30}{e['elapsed_ns']/1e6:>10.2f}m"
          f"{e['noise']*100:>7.1f}%{e['drift_sigma']*100:>8.1f}%"
          f"{band(e)*100:>6.0f}%")
bs = [band(e) for e in benches.values()]
print(f"\n{len(benches)} benches | band: min {min(bs)*100:.0f}%  "
      f"median {st.median(bs)*100:.0f}%  max {max(bs)*100:.0f}%")
missing = sorted(seen - set(benches))
if missing:
    print("\nNOT baselined — these fall back to the wide default band "
          "and are effectively ungated:")
    for n in missing:
        why = ", ".join(sorted(unusable.get(n, {"unknown"})))
        print(f"  {n:28} {why}")
PY
echo ""
echo "wrote baselines.json"
