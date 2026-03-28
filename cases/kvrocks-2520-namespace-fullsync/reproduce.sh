#!/usr/bin/env bash
# Reproduction and verification script for kvrocks-2520-namespace-fullsync
# Injects the regression Go test from the fix PR (apache/kvrocks#2527) into
# the kvrocks Go test suite, runs it against the current binary, and
# reports PASS/FAIL.
# ── Docker mode (preferred) ──
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
    exec "$REPO_ROOT/bench.sh" reproduce "$CASE_NAME"
fi
# ── Host fallback (no Docker) ──
set -uo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/kvrocks-2520-namespace-fullsync"
BINARY="$WORK_DIR/build/kvrocks"
TEST_FILE="$WORK_DIR/tests/gocase/unit/namespace/namespace_fullsync_bug_test.go"

export PATH="/usr/local/go/bin:$PATH"

# ── Rebuild if source changed ──
[ -f "$WORK_DIR/REBUILD.sh" ] && bash "$WORK_DIR/REBUILD.sh"

# Verify setup
if [ ! -x "$BINARY" ]; then
    echo "ERROR: Binary not found at $BINARY. Run ./setup.sh first."
    exit 1
fi

echo "=== Reproducing kvrocks-2520-namespace-fullsync ==="

cleanup() {
    rm -f "$TEST_FILE"
    pkill -f "kvrocks" 2>/dev/null || true
}
trap cleanup EXIT

# Check if the test already exists in the codebase (the fix commit adds it).
# Only inject if it doesn't exist — avoids redeclaration errors.
EXISTING_TEST="$WORK_DIR/tests/gocase/unit/namespace/namespace_test.go"
if grep -q "TestNamespaceReplicateWithFullSync" "$EXISTING_TEST" 2>/dev/null; then
    echo "Test already exists in codebase (fix commit), skipping injection."
else
    cp /bench/inject_test.go "$TEST_FILE" 2>/dev/null || cp "$CASE_DIR/inject_test.go" "$TEST_FILE"
    echo "Injected regression test: $TEST_FILE"
fi
echo "Running Go test TestNamespaceReplicateWithFullSync..."

cd "$WORK_DIR/tests/gocase"

# The kvrocks Go test framework requires -binPath (kvrocks binary) and -workspace (temp dir).
TEST_WORKSPACE=$(mktemp -d)
OUTPUT=$(go test -v -run "^TestNamespaceReplicateWithFullSync$" -count=1 -timeout 120s ./unit/namespace/ -binPath "$BINARY" -workspace "$TEST_WORKSPACE" -deleteOnExit 2>&1)
rm -rf "$TEST_WORKSPACE"
echo "$OUTPUT" | tail -20

# Clean up injected test
rm -f "$TEST_FILE"

echo ""
if echo "$OUTPUT" | grep -q "FAIL"; then
    echo "FAIL: Bug is present — namespaces not visible on slave after full sync"
    exit 1
else
    echo "PASS: Bug is fixed — namespaces correctly loaded after full sync"
    exit 0
fi
