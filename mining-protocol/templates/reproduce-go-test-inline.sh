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

cd "$WORK_DIR/GO_MODULE_ROOT"
OUTPUT=$(go test -v -run "^TEST_FUNC_NAME$" -count=1 -timeout 60s ./GO_PACKAGE_PATH/ 2>&1)
TEST_EXIT=$?
echo "$OUTPUT"

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
