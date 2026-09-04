#!/usr/bin/env bash
# run.sh — Hale bench harness.
#
# Builds each bench under micro/ and app/, runs it N times,
# takes the median of elapsed_ns + maxrss_kb, compares against
# the checked-in baseline with a per-bench tolerance band, emits
# a JSON report to results/, and exits non-zero on regression.
#
# Comparative timing: for each <name>.hl, the harness also runs
# any sibling <name>.go / <name>.js / <name>.py whose toolchain
# is on PATH. The other-language numbers are emitted alongside
# Hale's in the JSON report and printed as a ratio_vs_hale
# line per language. Comparative results are informational only
# — they never gate exit code (per spec/testing.md Layer 3:
# "a regression in hale-vs-X ratio is a developer signal, not
# a CI gate").
#
# Usage:
#   ./run.sh                     # run all + comparatives, exit on Hale regression
#   ./run.sh --update-baselines  # overwrite baselines.json with new medians
#   ./run.sh --bench=NAME        # run a single named bench
#   ./run.sh --iters=N           # samples per bench (default 11)
#   ./run.sh --no-build          # skip rebuilding (use stale binaries)
#   ./run.sh --no-comparative    # Hale only, skip go/node/python siblings
#   ./run.sh --json              # quieter; JSON-only stdout

set -euo pipefail

BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Locate the hale binary. Priority (2026-07-28 fix):
#   1. HALE_BIN=/path/to/hale     — explicit override, always wins
#   2. ../hale/target/release/hale — the sibling DEV checkout
#   3. `hale` on PATH              — the installed release
# The old order preferred PATH over the sibling checkout, so a
# machine with an installed release silently benchmarked THAT
# instead of the tree being developed — an A/B where both sides
# ran the same stale binary measured a compiler regression as
# "pre-existing" for four releases. The resolved binary + its
# version are echoed (stderr, so --json stdout stays clean);
# read that line before trusting any number.
if [[ -n "${HALE_BIN:-}" ]]; then
    HALE="$HALE_BIN"
elif [[ -x "$BENCH_DIR/../hale/target/release/hale" ]]; then
    HALE="$BENCH_DIR/../hale/target/release/hale"
elif command -v hale >/dev/null 2>&1; then
    HALE="$(command -v hale)"
else
    echo "run.sh: no hale binary found (no HALE_BIN, no sibling" >&2
    echo "  ../hale/target/release/hale, none on PATH)" >&2
    exit 1
fi
if [[ ! -x "$HALE" ]]; then
    echo "run.sh: resolved hale binary is not executable: $HALE" >&2
    exit 1
fi
echo "hale: $HALE ($("$HALE" --version 2>/dev/null || echo 'version unknown'))" >&2
BASELINES="$BENCH_DIR/baselines.json"
RESULTS_DIR="$BENCH_DIR/results"

# 11, not 5. The median of 5 samples is itself a noisy statistic —
# one preempted run moves it. Every bench here runs in well under a
# second, so the extra samples cost seconds of wall clock and buy a
# median that does not move between runs of an unchanged binary.
ITERS=11
UPDATE_BASELINES=0
SINGLE_BENCH=""
SKIP_BUILD=0
JSON_ONLY=0
SKIP_COMPARATIVE=0

for arg in "$@"; do
    case "$arg" in
        --update-baselines) UPDATE_BASELINES=1 ;;
        --bench=*)          SINGLE_BENCH="${arg#--bench=}" ;;
        --iters=*)          ITERS="${arg#--iters=}" ;;
        --no-build)         SKIP_BUILD=1 ;;
        --no-comparative)   SKIP_COMPARATIVE=1 ;;
        --json)             JSON_ONLY=1 ;;
        -h|--help)
            sed -n 's/^# \?//p' "${BASH_SOURCE[0]}" | sed -n '1,40p'
            exit 0
            ;;
        *)
            echo "unknown arg: $arg" >&2
            exit 2
            ;;
    esac
done

log() { [ "$JSON_ONLY" -eq 1 ] || echo "$@" >&2; }

# Ensure prerequisites.
command -v jq >/dev/null || { echo "jq not found on PATH" >&2; exit 2; }
command -v /usr/bin/time >/dev/null || { echo "/usr/bin/time not found" >&2; exit 2; }
[ -x "$HALE" ] || { echo "hale CLI not built at $HALE" >&2; echo "run: cargo build --release -p hale-cli" >&2; exit 2; }

# Comparative toolchain detection — silent if absent. Each entry
# in this map is "lang:cmd" where the command must be on PATH.
declare -A LANG_AVAILABLE
have() { command -v "$1" >/dev/null 2>&1; }
if [ "$SKIP_COMPARATIVE" -eq 0 ]; then
    have go      && LANG_AVAILABLE[go]=1            || true
    have go      && LANG_AVAILABLE[go-idiomatic]=1  || true
    have node    && LANG_AVAILABLE[node]=1          || true
    have python3 && LANG_AVAILABLE[python]=1        || true
    # 2026-07-01 — the "competitive with Rust/C++" comparators.
    # rustc single-file (std only, no cargo); clang -O3 native.
    have rustc   && LANG_AVAILABLE[rust]=1          || true
    have clang   && LANG_AVAILABLE[c]=1             || true
fi

mkdir -p "$RESULTS_DIR"

# Discover benches as "kind:relative_path" pairs.
benches=()
for f in "$BENCH_DIR/micro"/*.hl; do
    [ -f "$f" ] || continue
    benches+=("micro:$f")
done
for f in "$BENCH_DIR/app"/*.hl; do
    [ -f "$f" ] || continue
    benches+=("app:$f")
done

# Median of an array of integers.
median() {
    local sorted
    sorted=$(printf '%s\n' "$@" | sort -n)
    local n
    n=$(echo "$sorted" | wc -l)
    local mid=$(( (n + 1) / 2 ))
    echo "$sorted" | sed -n "${mid}p"
}

# Relative standard error of the MEDIAN, as a fraction.
#
#   1.253 * stdev / sqrt(n) / median
#
# This is the number a tolerance band should be built from, and the
# reason is the whole point of hale-lang/hale#522: raw sample spread
# is not the uncertainty of the median. `fn_modular` samples swing
# 18% run to run while its median is stable to about 2%, because a
# median over 11 samples averages the jitter out. Building a band
# from the spread produces a 50%+ window on a bench that can resolve
# a 5% change — which is how a real 29% regression passed the gate
# for five releases.
#
# The 1.253 factor is the asymptotic efficiency of the median
# relative to the mean for a normal sample. Timing distributions are
# not normal — they are right-skewed with occasional long tails — so
# this UNDERSTATES the true uncertainty a little; NOISE_K and the
# run-time guard below absorb that.
median_se() {
    printf '%s\n' "$@" | sort -n | awk '
        { a[NR] = $1; sum += $1 }
        END {
            if (NR < 2) { print "0"; exit }
            mid = int((NR + 1) / 2); med = a[mid];
            if (med <= 0) { print "0"; exit }
            mean = sum / NR;
            for (i = 1; i <= NR; i++) { d = a[i] - mean; ss += d * d }
            printf "%.4f", 1.253 * sqrt(ss / NR) / sqrt(NR) / med
        }'
}

# Turn a bench recording into its tolerance band.
#
# The band used to be a hand-set constant (default 0.30) that
# --update-baselines carried forward verbatim, so it never tracked
# what a bench could actually resolve. fn_modular pins its median to
# ~2% and had a 30% band: a REAL 29% regression passed with a point
# to spare and survived five releases (hale-lang/hale#522).
#
# Two noise terms, because there are two independent sources and the
# smaller one is the tempting one to stop at:
#
#   noise  within-run standard error of the median — how well ONE
#          run pins its own number. 0.3-3.5% across this suite.
#   drift  between-run movement of that median on an UNCHANGED
#          binary — machine state the samples inside a run all
#          share and therefore cannot see. 0-25%, median ~5%.
#
# Drift dominates by 3-5x, so a band built from `noise` alone fires
# on the next run of the same compiler. That is not hypothetical:
# it produced three false regressions the first time this was tried.
#
# `tolerance_override` in baselines.json wins over all of it, for a
# bench that is known-pathological for a reason worth writing down.
NOISE_K=${NOISE_K:-4}
DRIFT_K=${DRIFT_K:-2}
NOISE_FLOOR=${NOISE_FLOOR:-0.05}
NOISE_CEIL=${NOISE_CEIL:-0.35}

band_from_noise() {
    awk -v n="$1" -v d="$2" -v kn="$NOISE_K" -v kd="$DRIFT_K" \
        -v lo="$NOISE_FLOOR" -v hi="$NOISE_CEIL" \
        'BEGIN {
            b = n * kn;
            if (d * kd > b) b = d * kd;
            if (b < lo) b = lo;
            if (b > hi) b = hi;
            printf "%.4f", b
        }'
}

# The band this run will judge `name` against.
resolve_tolerance() {
    local name="$1" override noise drift
    override=$(baseline_field "$name" "tolerance_override")
    if [ -n "$override" ]; then echo "$override"; return; fi
    noise=$(baseline_field "$name" "noise")
    drift=$(baseline_field "$name" "drift")
    if [ -n "$noise" ]; then
        band_from_noise "$noise" "${drift:-0}"
        return
    fi
    # No recorded noise (a bench added since the last baseline).
    # Fall back to the old wide default rather than inventing a
    # tight band from a measurement that was never taken.
    echo "0.30"
}

# Look up a numeric field on a bench in baselines.json. Empty if absent.
baseline_field() {
    local name="$1"; local field="$2"
    [ -f "$BASELINES" ] || { echo ""; return; }
    jq -r --arg n "$name" --arg f "$field" \
        '.benches[$n][$f] // empty' "$BASELINES" 2>/dev/null
}

# Run a binary N times with /usr/bin/time -v. Populates globals:
#   _RUN_STATUS         — "ok" or "fail"
#   _RUN_ELAPSED_MEDIAN — median elapsed_ns
#   _RUN_MAXRSS_MEDIAN  — median maxrss_kb
#   _RUN_ELAPSED_JSON   — JSON array of samples
#   _RUN_MAXRSS_JSON    — JSON array of samples
# The binary must print exactly one `elapsed_ns=N` line on stdout.
time_binary() {
    local bin="$1"
    local n_iters="$2"
    shift 2
    local prefix_args=("$@")   # optional argv prefix (e.g. interpreter + script)

    local elapsed_samples=()
    local maxrss_samples=()
    local time_out
    for ((__r=1; __r<=n_iters; __r++)); do
        time_out=$(mktemp)
        if ! /usr/bin/time -f "__BENCH_TIME__ wall=%e maxrss=%M" \
                "${prefix_args[@]}" "$bin" >"$time_out.out" 2>"$time_out.err"; then
            _RUN_STATUS="fail"
            cat "$time_out.err" >&2
            rm -f "$time_out" "$time_out.out" "$time_out.err"
            return 0
        fi
        local elapsed maxrss
        elapsed=$(grep -oE 'elapsed_ns=[0-9]+' "$time_out.out" | head -1 | cut -d= -f2 || true)
        maxrss=$(grep -oE '__BENCH_TIME__ wall=[0-9.]+ maxrss=[0-9]+' "$time_out.err" | grep -oE 'maxrss=[0-9]+' | cut -d= -f2 || true)
        rm -f "$time_out" "$time_out.out" "$time_out.err"
        if [ -z "$elapsed" ] || [ -z "$maxrss" ]; then
            _RUN_STATUS="fail"
            return 0
        fi
        elapsed_samples+=("$elapsed")
        maxrss_samples+=("$maxrss")
    done

    _RUN_STATUS="ok"
    _RUN_ELAPSED_MEDIAN=$(median "${elapsed_samples[@]}")
    _RUN_MAXRSS_MEDIAN=$(median "${maxrss_samples[@]}")
    _RUN_ELAPSED_SE=$(median_se "${elapsed_samples[@]}")
    _RUN_ELAPSED_JSON=$(printf '%s\n' "${elapsed_samples[@]}" | jq -s .)
    _RUN_MAXRSS_JSON=$(printf '%s\n' "${maxrss_samples[@]}" | jq -s .)
}

# Per-run results gathered as one JSON object per bench.
results_json="[]"
regression_count=0
inconclusive_count=0

for entry in "${benches[@]}"; do
    kind="${entry%%:*}"
    src="${entry#*:}"
    name="$(basename "$src" .hl)"
    src_dir="$(dirname "$src")"

    if [ -n "$SINGLE_BENCH" ] && [ "$name" != "$SINGLE_BENCH" ]; then
        continue
    fi

    bin="${src%.hl}"

    # Build the Hale binary (or trust an existing one).
    if [ "$SKIP_BUILD" -eq 0 ]; then
        log "[$kind/$name] building"
        if ! HALE_SKIP_STALE_CHECK=1 "$HALE" build "$src" >/dev/null 2>&1; then
            log "[$kind/$name] HALE BUILD FAILED — skipping"
            results_json=$(jq --arg n "$name" --arg k "$kind" \
                '. + [{name: $n, kind: $k, status: "build_failed"}]' \
                <<<"$results_json")
            continue
        fi
    fi

    if [ ! -x "$bin" ]; then
        log "[$kind/$name] hale binary missing at $bin — skipping"
        continue
    fi

    # Time the Hale binary.
    time_binary "$bin" "$ITERS"
    if [ "$_RUN_STATUS" != "ok" ]; then
        log "[$kind/$name] HALE RUN FAILED"
        results_json=$(jq --arg n "$name" --arg k "$kind" \
            '. + [{name: $n, kind: $k, status: "run_failed"}]' \
            <<<"$results_json")
        continue
    fi

    hale_elapsed="$_RUN_ELAPSED_MEDIAN"
    hale_maxrss="$_RUN_MAXRSS_MEDIAN"
    hale_elapsed_json="$_RUN_ELAPSED_JSON"
    hale_maxrss_json="$_RUN_MAXRSS_JSON"

    # Compare against baseline.
    baseline_elapsed=$(baseline_field "$name" "elapsed_ns")
    baseline_maxrss=$(baseline_field "$name" "maxrss_kb")
    tolerance=$(resolve_tolerance "$name")
    status="ok"
    regression_note=""

    if [ -n "$baseline_elapsed" ] && [ "$UPDATE_BASELINES" -eq 0 ]; then
        if awk -v cur="$hale_elapsed" -v base="$baseline_elapsed" -v tol="$tolerance" \
            'BEGIN { exit (cur > base * (1.0 + tol)) ? 0 : 1 }'; then
            pct=$(awk -v cur="$hale_elapsed" -v base="$baseline_elapsed" \
                'BEGIN { printf "%.1f", (cur/base - 1.0) * 100.0 }')
            # NOISE GUARD. A regression is only reported when this run's
            # own median uncertainty is smaller than the tolerance
            # band. If the median is less certain than the band it is
            # being asked to resolve, "regression" would be a coin
            # flip.
            #
            # This is not hypothetical: coord_with_churn reported
            # +35.1% against a BYTE-IDENTICAL binary (issue #6), on a
            # bench whose own samples span >50%.
            if awk -v sp="$_RUN_ELAPSED_SE" -v tol="$tolerance" \
                'BEGIN { exit (sp < tol) ? 0 : 1 }'; then
                status="regression"
                regression_note="elapsed_ns ${hale_elapsed} > baseline ${baseline_elapsed} (+${pct}%, tol ${tolerance}, median SE ${_RUN_ELAPSED_SE})"
                regression_count=$((regression_count + 1))
                log "[$kind/$name] REGRESSION: $regression_note"
            else
                status="inconclusive"
                regression_note="elapsed_ns ${hale_elapsed} vs baseline ${baseline_elapsed} (+${pct}%) but median SE ${_RUN_ELAPSED_SE} >= tol ${tolerance} — cannot resolve; raise --iters"
                inconclusive_count=$((inconclusive_count + 1))
                log "[$kind/$name] INCONCLUSIVE: $regression_note"
            fi
        fi
    fi

    log "[$kind/$name] hale  elapsed_ns=$hale_elapsed maxrss_kb=$hale_maxrss status=$status"

    # Comparatives: for each language with sibling source AND
    # toolchain present, build (Go) and run N times.
    # `go-idiomatic` looks for <stem>.idiomatic.go and gets the
    # same build path as plain `go`. Benches that don't ship an
    # idiomatic.go sibling silently skip this column.
    comparatives_json="{}"
    for lang in c rust go go-idiomatic node python; do
        [ -n "${LANG_AVAILABLE[$lang]:-}" ] || continue
        case "$lang" in
            c)             ext="c" ;;
            rust)          ext="rs" ;;
            go)            ext="go" ;;
            go-idiomatic)  ext="idiomatic.go" ;;
            node)          ext="js" ;;
            python)        ext="py" ;;
        esac
        sibling="$src_dir/$name.$ext"
        [ -f "$sibling" ] || continue

        if [ "$lang" = "go" ] || [ "$lang" = "go-idiomatic" ]; then
            go_bin="$src_dir/${name}.${ext}.bin"
            if [ "$SKIP_BUILD" -eq 0 ]; then
                if ! ( cd "$src_dir" && go build -o "$go_bin" "$name.$ext" >/dev/null 2>&1 ); then
                    log "[$kind/$name] $lang BUILD FAILED — skipping"
                    continue
                fi
            fi
            [ -x "$go_bin" ] || { log "[$kind/$name] $lang binary missing — skipping"; continue; }
            time_binary "$go_bin" "$ITERS"
        elif [ "$lang" = "c" ]; then
            # clang -O3 -march=native mirrors Hale's default codegen
            # posture (O3 + host tuning) so the comparison is
            # toolchain-fair.
            c_bin="$src_dir/${name}.c.cbin"
            if [ "$SKIP_BUILD" -eq 0 ]; then
                if ! clang -O3 -march=native -o "$c_bin" "$sibling" -lm -lpthread >/dev/null 2>&1; then
                    log "[$kind/$name] $lang BUILD FAILED — skipping"
                    continue
                fi
            fi
            [ -x "$c_bin" ] || { log "[$kind/$name] $lang binary missing — skipping"; continue; }
            time_binary "$c_bin" "$ITERS"
        elif [ "$lang" = "rust" ]; then
            # Single-file rustc (std only, no cargo): -O + host CPU
            # tuning for parity with Hale/C.
            rs_bin="$src_dir/${name}.rs.bin"
            if [ "$SKIP_BUILD" -eq 0 ]; then
                if ! rustc -O -C target-cpu=native -o "$rs_bin" "$sibling" >/dev/null 2>&1; then
                    log "[$kind/$name] $lang BUILD FAILED — skipping"
                    continue
                fi
            fi
            [ -x "$rs_bin" ] || { log "[$kind/$name] $lang binary missing — skipping"; continue; }
            time_binary "$rs_bin" "$ITERS"
        elif [ "$lang" = "node" ]; then
            time_binary "$sibling" "$ITERS" node
        elif [ "$lang" = "python" ]; then
            time_binary "$sibling" "$ITERS" python3
        fi

        if [ "$_RUN_STATUS" != "ok" ]; then
            log "[$kind/$name] $lang RUN FAILED — skipping"
            continue
        fi

        lang_elapsed="$_RUN_ELAPSED_MEDIAN"
        lang_maxrss="$_RUN_MAXRSS_MEDIAN"
        lang_elapsed_json="$_RUN_ELAPSED_JSON"
        lang_maxrss_json="$_RUN_MAXRSS_JSON"

        # ratio_vs_hale = lang_elapsed / hale_elapsed.
        # < 1.0 means this language is faster than Hale.
        # > 1.0 means Hale is faster than this language.
        ratio=$(awk -v lang="$lang_elapsed" -v ap="$hale_elapsed" \
            'BEGIN { if (ap == 0) print "null"; else printf "%.4f", lang / ap }')
        log "[$kind/$name] $(printf '%-14s' "$lang:") elapsed_ns=$(printf '%-14s' "$lang_elapsed") ratio_vs_hale=${ratio}x"

        comparatives_json=$(jq \
            --arg lang "$lang" \
            --argjson em "$lang_elapsed" --argjson rm "$lang_maxrss" \
            --argjson es "$lang_elapsed_json" --argjson rs "$lang_maxrss_json" \
            --argjson ratio "$ratio" \
            '. + {($lang): {
                elapsed_ns_median: $em, elapsed_ns_samples: $es,
                maxrss_kb_median: $rm, maxrss_kb_samples: $rs,
                ratio_vs_hale: $ratio
            }}' \
            <<<"$comparatives_json")
    done

    results_json=$(jq \
        --arg n "$name" --arg k "$kind" --arg s "$status" \
        --arg note "$regression_note" \
        --argjson em "$hale_elapsed" --argjson rm "$hale_maxrss" \
        --argjson es "$hale_elapsed_json" \
        --argjson rs "$hale_maxrss_json" \
        --argjson be "${baseline_elapsed:-null}" \
        --argjson br "${baseline_maxrss:-null}" \
        --argjson sp "${_RUN_ELAPSED_SE:-0}" \
        --argjson tol "$tolerance" \
        --argjson comps "$comparatives_json" \
        '. + [{
            name: $n, kind: $k, status: $s,
            elapsed_ns_median: $em, elapsed_ns_samples: $es,
            elapsed_median_se: $sp, tolerance: $tol,
            maxrss_kb_median: $rm, maxrss_kb_samples: $rs,
            baseline_elapsed_ns: $be, baseline_maxrss_kb: $br,
            note: (if $note == "" then null else $note end),
            comparatives: $comps
        }]' \
        <<<"$results_json")
done

# Write report.
timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
report=$(jq --arg t "$timestamp" --argjson iters "$ITERS" \
    '{generated_at: $t, iters: $iters, benches: .}' <<<"$results_json")

results_path="$RESULTS_DIR/run-$(date -u +%Y%m%d-%H%M%S).json"
echo "$report" > "$results_path"

if [ "$JSON_ONLY" -eq 1 ]; then
    echo "$report"
else
    log ""
    log "Report: $results_path"
fi

# Update baselines if requested.
#
# REFUSED from here on. A baseline needs the between-run drift term,
# and a single run cannot measure it — every sample in one run shares
# the machine state that drift IS. Baselining from one run produced
# bands that fired on the very next run of the same binary.
# `rebaseline.sh` does N runs and records both terms.
if [ "$UPDATE_BASELINES" -eq 1 ]; then
    log ""
    log "run.sh --update-baselines is retired: a single run cannot"
    log "measure between-run drift, and a band without it fires on"
    log "the next run of the same binary. Use:"
    log ""
    log "    ./rebaseline.sh [runs] [iters]      # default 3 x 21"
    log ""
    exit 2
fi

# Inconclusive benches are surfaced but never gate: the run said
# "I cannot tell", which is information, not a failure. A bench that
# is persistently inconclusive needs a wider measurement window or a
# tolerance matched to its real precision — see issues #6 and #7.
if [ "$inconclusive_count" -gt 0 ]; then
    log ""
    log "NOTE: $inconclusive_count bench(es) INCONCLUSIVE — median uncertainty exceeded the tolerance band, so a regression could not be distinguished from noise"
fi

# Exit non-zero on Hale regression (comparative numbers never gate).
if [ "$UPDATE_BASELINES" -eq 0 ] && [ "$regression_count" -gt 0 ]; then
    log ""
    log "FAILED: $regression_count regression(s) detected"
    exit 1
fi
