#!/usr/bin/env bash
# Reproduction and verification script for raft-581-transfer-write-race
# Injects a test into the raft package that performs leadership transfers
# under concurrent write load and checks whether writes sneak through
# when the transfer-in-progress flag should be blocking them.
# ── Docker mode (preferred) ──
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
  exec "$REPO_ROOT/bench.sh" reproduce "$CASE_NAME"
fi
# ── Host fallback (no Docker) ──
set -uo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/raft-581-transfer-write-race"
TEST_FILE="$WORK_DIR/transfer_writes_bug_test.go"
export PATH="$PATH:/usr/local/go/bin"

# ── Rebuild if source changed ──
[ -f "$WORK_DIR/REBUILD.sh" ] && bash "$WORK_DIR/REBUILD.sh"

# Verify setup
if [ ! -d "$WORK_DIR" ]; then
  echo "ERROR: Work directory not found at $WORK_DIR. Run ./setup.sh first."
  exit 1
fi

echo "=== Reproducing raft-581-transfer-write-race ==="

cleanup() {
  rm -f "$TEST_FILE"
}
trap cleanup EXIT

# Inject the test into the raft package
cp /bench/inject_test.go "$TEST_FILE" 2>/dev/null || cp "$CASE_DIR/inject_test.go" "$TEST_FILE"

cd "$WORK_DIR"

# Run the test 5 times. On the buggy commit, writes succeed during the
# transfer window because the flag is cleared too early. On the fixed
# commit, writes are blocked by ErrLeadershipTransferInProgress.
FAILURES=0
TOTAL=10

for i in $(seq 1 $TOTAL); do
  echo "=== Run $i/$TOTAL ==="
  OUTPUT=$(timeout 120 go test -v -run "^TestLeadershipTransferWritesDuringTransfer$" -count=1 -timeout 90s . 2>&1)
  EXIT_CODE=$?

  # Show key output
  echo "$OUTPUT" | grep -E "Transfer failures|Bug present|PASS|FAIL" | head -5

  if [ $EXIT_CODE -ne 0 ]; then
    FAILURES=$((FAILURES + 1))
    echo "  -> FAILED (writes leaked through during transfer)"
  else
    echo "  -> OK"
  fi
done

echo ""
if [ $FAILURES -gt 0 ]; then
  echo "FAIL: Bug is present — $FAILURES/$TOTAL runs detected writes leaking through during leadership transfer"
  exit 1
else
  echo "PASS: Bug is fixed — writes correctly blocked during leadership transfer in all $TOTAL runs"
  exit 0
fi
