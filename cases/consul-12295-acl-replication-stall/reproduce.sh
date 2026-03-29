#!/usr/bin/env bash
# Reproduction and verification script for consul-12295-acl-replication-stall
# Injects a test into lib/routine/ that exercises the IsRunning() lifecycle
# after the parent context is cancelled while a goroutine is still blocking on
# a long-running call (simulating a cross-DC ACL replication RPC). On the buggy
# commit, IsRunning() returns true even after the parent context is done, causing
# startACLReplication() to skip restarting the ACL replication routines after a
# server loses and immediately regains leadership.
# ── Docker mode (preferred) ──
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
    exec "$REPO_ROOT/bench.sh" reproduce "$CASE_NAME"
fi
# ── Host fallback (no Docker) ──
set -uo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/consul-12295-acl-replication-stall"
TEST_FILE="$WORK_DIR/lib/routine/inject_test.go"
TEST_NAME="TestManager_IsRunningAfterParentContextCancel"

export PATH="$PATH:/usr/local/go/bin"

# ── Rebuild if source changed ──
[ -f "$WORK_DIR/REBUILD.sh" ] && bash "$WORK_DIR/REBUILD.sh"

# Verify setup
if [ ! -d "$WORK_DIR" ]; then
    echo "ERROR: Work directory not found at $WORK_DIR. Run ./setup.sh first."
    exit 1
fi

echo "=== Reproducing consul-12295-acl-replication-stall ==="

INJECTED=false
cleanup() {
    [ "$INJECTED" = true ] && rm -f "$TEST_FILE"
}
trap cleanup EXIT

# Inject the test if it doesn't already exist (fix commit may add a different test)
if grep -rq "func ${TEST_NAME}" "$WORK_DIR/lib/routine/"*_test.go 2>/dev/null; then
    echo "Test $TEST_NAME already exists in source — skipping injection"
else
    INJECTED=true
    cp /bench/inject_test.go "$TEST_FILE" 2>/dev/null || cp "$CASE_DIR/inject_test.go" "$TEST_FILE"
    echo "Injected regression test: $TEST_FILE"
fi

cd "$WORK_DIR"

echo "Running test $TEST_NAME..."
OUTPUT=$(go test -v -run "^${TEST_NAME}$" -count=1 -timeout 60s ./lib/routine/ 2>&1) || true

echo "$OUTPUT" | tail -30

echo ""
if echo "$OUTPUT" | grep -q "^--- PASS:"; then
    echo "PASS: Bug is fixed — IsRunning() correctly returns false after parent context cancelled"
    exit 0
else
    echo "FAIL: Bug is present — IsRunning() returns true after parent context cancelled, ACL replication will not restart after leadership re-election"
    exit 1
fi
