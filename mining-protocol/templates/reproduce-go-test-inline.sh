#!/usr/bin/env bash
# Reproduction and verification script for CASE_NAME
# Injects a regression test inline and runs it against the buggy codebase.
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

# Inject regression test
cat > "$TEST_FILE" << 'GOEOF'
# TODO: Paste the Go test code here.
# The test should:
#   - Import only packages available at the buggy commit
#   - Use t.Fatalf("Bug present: ...") for the failure case
#   - Use t.Logf("OK: ...") for the success case
GOEOF

echo "Injected regression test: $TEST_FILE"
echo "Running go test in GO_PACKAGE_PATH..."


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
OUTPUT=$(go test -v -run "^TEST_FUNC_NAME$" -count=1 -timeout 60s ./GO_PACKAGE_PATH/ 2>&1)
TEST_EXIT=$?
echo "$OUTPUT"
go_build_guard "$OUTPUT"

# Clean up the injected test
rm -f "$TEST_FILE"

echo ""
if [ "$TEST_EXIT" -ne 0 ]; then
    echo "FAIL: Bug is present — FAIL_DESCRIPTION"
    exit 1
else
    echo "PASS: Bug is fixed — PASS_DESCRIPTION"
    exit 0
fi
