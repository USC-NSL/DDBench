#!/usr/bin/env bash
# Reproduction and verification script for raft-460-logcache-store-order
# Injects a test into the raft package that verifies LogCache does not cache
# log entries when the backend StoreLogs() call fails.
# ── Docker mode (preferred) ──
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
    exec "$REPO_ROOT/bench.sh" reproduce "$CASE_NAME"
fi
# ── Host fallback (no Docker) ──
set -uo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/raft-460-logcache-store-order"
TEST_FILE="$WORK_DIR/logcache_store_order_bug_test.go"
export PATH="$PATH:/usr/local/go/bin"

# ── Rebuild if source changed ──
[ -f "$WORK_DIR/REBUILD.sh" ] && bash "$WORK_DIR/REBUILD.sh"

# Verify setup
if [ ! -d "$WORK_DIR" ]; then
    echo "ERROR: Work directory not found at $WORK_DIR. Run ./setup.sh first."
    exit 1
fi

echo "=== Reproducing raft-460-logcache-store-order ==="

cleanup() {
    rm -f "$TEST_FILE"
}
trap cleanup EXIT

# Inject the test into the raft package
cp /bench/inject_test.go "$TEST_FILE" 2>/dev/null || cp "$CASE_DIR/inject_test.go" "$TEST_FILE"

cd "$WORK_DIR"

# Run the unit test.
#
# On buggy code: LogCache populates the ring buffer before calling the
# backend's StoreLogs(). When the backend fails, GetLog(5) returns the
# cached (but unpersisted) entry -> test FAILs.
#
# On fixed code: LogCache calls the backend's StoreLogs() first. On
# failure, the cache is not populated. GetLog(5) returns ErrLogNotFound
# -> test PASSes.
echo "Running TestLogCacheStaleDataOnStoreError..."
OUTPUT=$(timeout 60 go test -v -run "^TestLogCacheStaleDataOnStoreError$" -count=1 . 2>&1)
EXIT_CODE=$?

echo "$OUTPUT"

echo ""
if [ $EXIT_CODE -ne 0 ]; then
    echo "FAIL: Bug is present -- LogCache caches entries even when StoreLogs() fails (stale cache data)"
    exit 1
else
    echo "PASS: Bug is fixed -- LogCache does not cache entries when StoreLogs() fails"
    exit 0
fi
