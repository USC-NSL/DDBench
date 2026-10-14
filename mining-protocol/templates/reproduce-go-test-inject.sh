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
if [ -f "$WORK_DIR/REBUILD.sh" ] && ! bash "$WORK_DIR/REBUILD.sh"; then
    echo "FAIL: Bug is present — code under test does not build"; exit 1
fi

# Verify setup
if [ ! -d "$WORK_DIR" ]; then
    echo "ERROR: Work directory not found at $WORK_DIR. Run ./setup.sh first."
    exit 2
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


# Build check before judging. ERROR (exit 2) only when the oracle's own probe
# is broken: the injected test doesn't compile, or -run matches nothing. If the
# code under test doesn't build, that is FAIL (exit 1), e.g. a patch that breaks
# compilation. Never give the code under test the benefit of the doubt.
go_build_guard() {  # go_build_guard <go test output>; exits on a build problem
    local out="$1" inj errs
    inj="$(basename "$TEST_FILE")"
    if grep -qE '\[(build|setup) failed\]|^# |cannot find package|undefined:' <<<"$out"; then
        errs=$(grep -E '\.go:[0-9]+(:[0-9]+)?: ' <<<"$out")
        if [ -n "$errs" ] && ! grep -qv "$inj" <<<"$errs"; then
            echo "ERROR: injected oracle test does not compile against this code:"; head -10 <<<"$errs"; exit 2
        fi
        echo "FAIL: Bug is present — code under test does not compile:"; head -10 <<<"${errs:-$out}"; exit 1
    fi
    grep -q 'no tests to run' <<<"$out" && { echo "ERROR: -run pattern matched no tests"; exit 2; }
    return 0
}

cd "$WORK_DIR/GO_MODULE_ROOT"

FAILURES=0
TOTAL=TEST_ITERATIONS

for i in $(seq 1 $TOTAL); do
    echo "=== Run $i/$TOTAL ==="
    OUTPUT=$(timeout 120 go test -v -run "^TEST_FUNC_NAME$" -count=1 -timeout 90s ./GO_PACKAGE_PATH/ 2>&1)
    EXIT_CODE=$?
    go_build_guard "$OUTPUT"

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
