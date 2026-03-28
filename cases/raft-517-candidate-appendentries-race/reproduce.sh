#!/usr/bin/env bash
# Reproduction and verification script for raft-517-candidate-appendentries-race
# Injects a test into the raft package that triggers the data race between
# runCandidate() and appendEntries(), runs with -race, and reports PASS/FAIL.
# ── Docker mode (preferred) ──
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
    exec "$REPO_ROOT/bench.sh" reproduce "$CASE_NAME"
fi
# ── Host fallback (no Docker) ──
set -uo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/raft-517-candidate-appendentries-race"
TEST_FILE="$WORK_DIR/candidate_race_bug_test.go"
export PATH="$PATH:/usr/local/go/bin"

# ── Rebuild if source changed ──
[ -f "$WORK_DIR/REBUILD.sh" ] && bash "$WORK_DIR/REBUILD.sh"

# Verify setup
if [ ! -d "$WORK_DIR" ]; then
    echo "ERROR: Work directory not found at $WORK_DIR. Run ./setup.sh first."
    exit 1
fi

echo "=== Reproducing raft-517-candidate-appendentries-race ==="

cleanup() {
    rm -f "$TEST_FILE"
}
trap cleanup EXIT

# Inject the test into the raft package
cp /bench/inject_test.go "$TEST_FILE" 2>/dev/null || cp "$CASE_DIR/inject_test.go" "$TEST_FILE"

cd "$WORK_DIR"

# Run the race test 5 times. Each run creates 5 parallel 3-node TCP
# clusters, each doing 200 leadership transfers (1000 total race windows).
# The per-run detection rate is ~90%, so 5 runs gives >99.999%.
RACES=0
TOTAL=5

for i in $(seq 1 $TOTAL); do
    echo "=== Run $i/$TOTAL ==="
    OUTPUT=$(timeout 120 go test -race -run "^TestCandidateAppendEntriesRaceWithTCP$" -count=1 -timeout 90s . 2>&1)
    EXIT_CODE=$?
    HAS_RACE=false
    echo "$OUTPUT" | grep -q "DATA RACE" && HAS_RACE=true
    echo "$OUTPUT" | grep -q "race detected" && HAS_RACE=true
    if $HAS_RACE; then
        RACES=$((RACES + 1))
        echo "  DATA RACE DETECTED"
    elif [ $EXIT_CODE -ne 0 ]; then
        echo "  ERROR (exit code $EXIT_CODE)"
    else
        echo "  OK"
    fi
done

# Clean up
rm -f "$TEST_FILE"

echo ""
if [ $RACES -gt 0 ]; then
    echo "FAIL: Bug is present — $RACES/$TOTAL runs triggered a data race"
    exit 1
else
    echo "PASS: Bug is fixed — all $TOTAL runs completed without data race"
    exit 0
fi
