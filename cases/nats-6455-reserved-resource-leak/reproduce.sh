#!/usr/bin/env bash
# Reproduction and verification script for nats-6455-reserved-resource-leak
# Injects a Go test that triggers the reserved resource double-counting bug,
# runs it, and reports PASS/FAIL.
# ── Docker mode (preferred) ──
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
    exec "$REPO_ROOT/bench.sh" reproduce "$CASE_NAME"
fi
# ── Host fallback (no Docker) ──
set -uo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/nats-6455-reserved-resource-leak"
TEST_FILE="$WORK_DIR/server/reserved_resource_leak_test.go"
TEST_NAME="TestJetStreamClusterReservedResourcesAccountingAfterClusterReset"

export PATH=$PATH:/usr/local/go/bin

# ── Rebuild if source changed ──
[ -f "$WORK_DIR/REBUILD.sh" ] && bash "$WORK_DIR/REBUILD.sh"

# Verify setup
if [ ! -f "$WORK_DIR/nats-server" ]; then
    echo "ERROR: Binary not found at $WORK_DIR/nats-server. Run ./setup.sh first."
    exit 1
fi

cd "$WORK_DIR"

echo "=== Reproducing nats-6455-reserved-resource-leak ==="

cleanup() {
    [ "$INJECTED" = true ] && rm -f "$TEST_FILE"
}
INJECTED=false
trap cleanup EXIT

# Inject the test into the server package (skip if fix commit already includes it)
INJECTED=false
if ! grep -rq "func ${TEST_NAME}" server/*_test.go 2>/dev/null; then
    cp /bench/inject_test.go "$TEST_FILE" 2>/dev/null || cp "$CASE_DIR/inject_test.go" "$TEST_FILE"
    INJECTED=true
fi

# Run the test
echo "Running test $TEST_NAME..."
TEST_OUTPUT=$(go test -v -run "^${TEST_NAME}$" -count=1 -timeout 120s ./server/ 2>&1) || true

echo "$TEST_OUTPUT" | tail -30

echo ""
if echo "$TEST_OUTPUT" | grep -qE "^ok\s"; then
    echo "PASS: Bug is fixed — reserved resources correctly accounted after cluster reset"
    exit 0
else
    echo "FAIL: Bug is present — reserved resources double-counted after cluster reset"
    exit 1
fi
