#!/usr/bin/env bash
# score_surface.sh -- Score every case of a tier after agents have run on them.
#
# Usage: harness/score_surface.sh <surface> <results-dir> [options]
#
# Surfaces: tier1, tier2, tier3, all (comma-separated for combinations)
#
# Cases are scored one after another (each case has its own Docker volumes,
# but scoring builds are CPU-heavy). For scoring patch files in parallel use
# `bench.sh eval-all` instead.
#
# Output:
#   <results-dir>/<case>/result.json  per-case score (see score_case.sh)
#   <results-dir>/summary.json         aggregate (see aggregate_results.py)
#   <results-dir>/summary.md           human-readable report
set -euo pipefail

HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CASES_ROOT="${DDBENCH_ROOT:-$(cd "$HARNESS_DIR/.." && pwd)}"
REGISTRY="$CASES_ROOT/registry/case_registry.json"

usage() {
    cat <<EOF
Usage: $0 <surface> <results-dir> [options]

Surfaces (see registry/tier_definitions.md):
  tier1   core cases
  tier2   extended cases
  tier3   advanced cases
  all     all cases

Options:
  --no-extract   Skip patch extraction
  --no-reset     Don't reset worktrees after scoring
  --timeout N    Per-case oracle timeout in seconds (default: 3600)
  -h, --help     Show this help
EOF
    exit 2
}

[ $# -ge 2 ] || usage
SURFACE="$1"
RESULTS_DIR="$2"
shift 2

EXTRA_ARGS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --no-extract) EXTRA_ARGS+=(--no-extract); shift ;;
        --no-reset)   EXTRA_ARGS+=(--no-reset); shift ;;
        --timeout)    EXTRA_ARGS+=(--timeout "$2"); shift 2 ;;
        -h|--help)    usage ;;
        *)            echo "Unknown option: $1" >&2; usage ;;
    esac
done

CASE_LIST=$(python3 - "$SURFACE" "$REGISTRY" <<'PYTHON'
import json, sys
surface_arg, registry_path = sys.argv[1], sys.argv[2]
with open(registry_path) as f:
    cases = json.load(f)["cases"]
valid = {"tier1", "tier2", "tier3"}
wanted = None if surface_arg == "all" else set(surface_arg.split(","))
if wanted is not None and wanted - valid:
    print(f"Unknown surface: {', '.join(sorted(wanted - valid))}. Valid: tier1, tier2, tier3, all",
          file=sys.stderr)
    sys.exit(2)
for c in cases:
    if wanted is None or c.get("surface_membership") in wanted:
        print(c["case_id"])
PYTHON
)
TOTAL=$(printf '%s\n' "$CASE_LIST" | grep -c . || true)
[ "$TOTAL" -gt 0 ] || { echo "ERROR: No cases found for surface $SURFACE" >&2; exit 2; }

echo "=== Scoring surface $SURFACE ($TOTAL cases) ==="
echo "  Results directory: $RESULTS_DIR"
echo ""
mkdir -p "$RESULTS_DIR"

PASSED=0
FAILED=0
ERRORS=0
COUNT=0

for case_name in $CASE_LIST; do
    COUNT=$((COUNT + 1))
    echo "[$COUNT/$TOTAL] $case_name"
    if bash "$HARNESS_DIR/score_case.sh" "$case_name" "$RESULTS_DIR" ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"} 2>&1; then
        result_file="$RESULTS_DIR/$case_name/result.json"
        result=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("result","UNKNOWN"))' \
                 "$result_file" 2>/dev/null || echo UNKNOWN)
        case "$result" in
            PASS) PASSED=$((PASSED + 1)) ;;
            FAIL) FAILED=$((FAILED + 1)) ;;
            *)    ERRORS=$((ERRORS + 1)) ;;
        esac
    else
        ERRORS=$((ERRORS + 1))
        echo "  ERROR: score_case.sh failed for $case_name"
    fi
    echo ""
done

echo "=== Aggregating results ==="
python3 "$HARNESS_DIR/aggregate_results.py" "$RESULTS_DIR" "$REGISTRY"

SCORED=$((PASSED + FAILED))
echo ""
echo "=== Surface $SURFACE Scoring Complete ==="
echo "  Total:  $TOTAL"
echo "  Passed: $PASSED"
echo "  Failed: $FAILED"
echo "  Errors: $ERRORS (excluded from the pass rate)"
if [ "$SCORED" -gt 0 ]; then
    echo "  Pass rate: $(awk -v p="$PASSED" -v s="$SCORED" 'BEGIN { printf "%.1f%%", 100 * p / s }') ($PASSED/$SCORED scored)"
fi
echo ""
echo "  Results: $RESULTS_DIR/summary.json"
echo "  Report:  $RESULTS_DIR/summary.md"
