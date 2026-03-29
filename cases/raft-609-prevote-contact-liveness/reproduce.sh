#!/usr/bin/env bash
# Reproduction and verification script for raft-609-prevote-contact-liveness
# Injects a test into the raft package that verifies pre-vote requests
# do not refresh the last-contact timestamp, which would block elections.
# ── Docker mode (preferred) ──
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
    exec "$REPO_ROOT/bench.sh" reproduce "$CASE_NAME"
fi
# ── Host fallback (no Docker) ──
set -uo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/raft-609-prevote-contact-liveness"
TEST_FILE="$WORK_DIR/prevote_contact_bug_test.go"
export PATH="$PATH:/usr/local/go/bin"

# ── Rebuild if source changed ──
[ -f "$WORK_DIR/REBUILD.sh" ] && bash "$WORK_DIR/REBUILD.sh"

# Verify setup
if [ ! -d "$WORK_DIR" ]; then
    echo "ERROR: Work directory not found at $WORK_DIR. Run ./setup.sh first."
    exit 1
fi

echo "=== Reproducing raft-609-prevote-contact-liveness ==="

cleanup() {
    rm -f "$TEST_FILE"
}
trap cleanup EXIT

# Inject the test into the raft package
cp /bench/inject_test.go "$TEST_FILE" 2>/dev/null || cp "$CASE_DIR/inject_test.go" "$TEST_FILE"

cd "$WORK_DIR"

# Run the integration test. The test requires NetworkTransport (TCP) which
# is gated by INTEG_TESTS. We run 3 iterations for reliability.
#
# On buggy code: pre-vote requests refresh setLastContact(), preventing
# followers from timing out. No new leader can be elected -> test FAILs.
#
# On fixed code: pre-vote requests don't refresh last-contact. Followers
# time out normally and elect a new leader -> test PASSes.
FAILURES=0
TOTAL=3

for i in $(seq 1 $TOTAL); do
    echo "=== Run $i/$TOTAL ==="
    OUTPUT=$(INTEG_TESTS=1 timeout 120 go test -v -run "^TestPreVoteLeaderSpamBlocksElection$" -count=1 -timeout 90s . 2>&1)
    EXIT_CODE=$?

    # Show key output
    echo "$OUTPUT" | grep -E "PASS|FAIL|failed to find node|err:" | head -5

    if [ $EXIT_CODE -ne 0 ]; then
        FAILURES=$((FAILURES + 1))
        echo "  -> FAILED (followers could not elect a new leader — pre-vote spam blocked elections)"
    else
        echo "  -> OK (new leader elected despite pre-vote spam)"
    fi
done

echo ""
if [ $FAILURES -gt 0 ]; then
    echo "FAIL: Bug is present — $FAILURES/$TOTAL runs failed: pre-vote requests refresh last-contact, blocking new elections"
    exit 1
else
    echo "PASS: Bug is fixed — all $TOTAL runs succeeded: pre-vote requests do not block elections"
    exit 0
fi
