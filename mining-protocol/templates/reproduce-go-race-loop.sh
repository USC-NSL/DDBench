#!/usr/bin/env bash
# Reproduction and verification script for CASE_NAME
# Injects a Go test and runs it with -race detector in a loop.
# ── Docker mode (preferred) ──
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
    exec "$REPO_ROOT/bench.sh" reproduce "$CASE_NAME"
fi
# ── Host fallback (no Docker) ──
set -uo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/CASE_NAME"
TEST_FILE="$WORK_DIR/GO_PACKAGE_PATH/TEST_FILE_NAME_test.go"
OUTPUT_FILE=$(mktemp)

export PATH=$PATH:/usr/local/go/bin

# ── Rebuild if source changed ──
[ -f "$WORK_DIR/REBUILD.sh" ] && bash "$WORK_DIR/REBUILD.sh"

# Verify setup
if [ ! -d "$WORK_DIR" ]; then
    echo "ERROR: Work directory not found at $WORK_DIR. Run ./setup.sh first."
    exit 1
fi

cd "$WORK_DIR"

echo "=== Reproducing CASE_NAME ==="

cleanup() {
    rm -f "$TEST_FILE" "$OUTPUT_FILE"
}
trap cleanup EXIT

# Inject the test
cp /bench/inject_test.go "$TEST_FILE" 2>/dev/null || cp "$CASE_DIR/inject_test.go" "$TEST_FILE"

echo "Running TEST_FUNC_NAME with -race detector (up to RACE_ITERATIONS iterations)..."

DETECTED=0
TOTAL=RACE_ITERATIONS

for i in $(seq 1 $TOTAL); do
    echo "=== Run $i/$TOTAL ==="
    timeout 120 go test -race -run "^TEST_FUNC_NAME$" -count=1 -timeout 90s ./GO_PACKAGE_PATH/ > "$OUTPUT_FILE" 2>&1 || true

    HAS_RACE=false
    grep -q "DATA RACE" "$OUTPUT_FILE" && HAS_RACE=true
    grep -q "concurrent map" "$OUTPUT_FILE" && HAS_RACE=true
    grep -q "race detected" "$OUTPUT_FILE" && HAS_RACE=true

    if $HAS_RACE; then
        DETECTED=$((DETECTED + 1))
        echo "  RACE DETECTED"
        # Show relevant output
        grep -A 10 "DATA RACE\|concurrent map" "$OUTPUT_FILE" | head -20
    else
        echo "  OK"
    fi
done

rm -f "$TEST_FILE"

echo ""
if [ $DETECTED -gt 0 ]; then
    echo "FAIL: Bug is present — $DETECTED/$TOTAL runs triggered a data race"
    exit 1
else
    echo "PASS: Bug is fixed — all $TOTAL runs completed without data race"
    exit 0
fi
