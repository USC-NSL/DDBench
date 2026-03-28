#!/usr/bin/env bash
# Reproduction and verification script for CASE_NAME
# Injects a Go test from inject_test.go and runs it with a loop.
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

export PATH="$PATH:/usr/local/go/bin"

# ── Rebuild if source changed ──
[ -f "$WORK_DIR/REBUILD.sh" ] && bash "$WORK_DIR/REBUILD.sh"

# Verify setup
if [ ! -d "$WORK_DIR" ]; then
    echo "ERROR: Work directory not found at $WORK_DIR. Run ./setup.sh first."
    exit 1
fi

echo "=== Reproducing CASE_NAME ==="

cleanup() {
    rm -f "$TEST_FILE"
}
trap cleanup EXIT

# Check if the test already exists in the codebase (fix commit may add it).
# Only inject if it doesn't exist — avoids redeclaration errors.
EXISTING_TEST="$WORK_DIR/GO_PACKAGE_PATH/EXISTING_TEST_FILE.go"
if grep -q "TEST_FUNC_NAME" "$EXISTING_TEST" 2>/dev/null; then
    echo "Test already exists in codebase (fix commit), skipping injection."
else
    cp /bench/inject_test.go "$TEST_FILE" 2>/dev/null || cp "$CASE_DIR/inject_test.go" "$TEST_FILE"
    echo "Injected regression test: $TEST_FILE"
fi

cd "$WORK_DIR/GO_MODULE_ROOT"

FAILURES=0
TOTAL=TEST_ITERATIONS

for i in $(seq 1 $TOTAL); do
    echo "=== Run $i/$TOTAL ==="
    OUTPUT=$(timeout 120 go test -v -run "^TEST_FUNC_NAME$" -count=1 -timeout 90s ./GO_PACKAGE_PATH/ 2>&1)
    EXIT_CODE=$?

    echo "$OUTPUT" | grep -E "PASS|FAIL|Bug present" | head -5

    if [ $EXIT_CODE -ne 0 ]; then
        FAILURES=$((FAILURES + 1))
        echo "  -> FAILED"
    else
        echo "  -> OK"
    fi
done

rm -f "$TEST_FILE"

echo ""
if [ $FAILURES -gt 0 ]; then
    echo "FAIL: Bug is present — $FAILURES/$TOTAL runs detected the bug"
    exit 1
else
    echo "PASS: Bug is fixed — all $TOTAL runs passed"
    exit 0
fi
