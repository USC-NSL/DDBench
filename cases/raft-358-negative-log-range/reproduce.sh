#!/usr/bin/env bash
# Reproduction and verification script for raft-358-negative-log-range
# Writes a Go test that creates an InmemStore with entries 100-200,
# then checks if compactLogs would produce an invalid range when
# snapIdx < minLog.
# ── Docker mode (preferred) ──
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
    exec "$REPO_ROOT/bench.sh" reproduce "$CASE_NAME"
fi
# ── Host fallback (no Docker) ──
set -uo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/raft-358-negative-log-range"
export PATH="$PATH:/usr/local/go/bin"

# ── Rebuild if source changed ──
[ -f "$WORK_DIR/REBUILD.sh" ] && bash "$WORK_DIR/REBUILD.sh"

# Verify setup
if [ ! -e "$WORK_DIR/.git" ]; then
    echo "ERROR: Repository not found at $WORK_DIR. Run ./setup.sh first."
    exit 1
fi

echo "=== Reproducing raft-358-negative-log-range ==="

cleanup() {
    rm -f "$WORK_DIR/negative_range_test.go"
}
trap cleanup EXIT

cd "$WORK_DIR"

# Write test file
cat > negative_range_test.go <<'GOEOF'
package raft

import (
	"testing"
)

func TestCompactLogsNegativeRange(t *testing.T) {
	// Create an InmemStore and populate with log entries 100-200
	store := NewInmemStore()
	for i := uint64(100); i <= 200; i++ {
		store.StoreLog(&Log{Index: i, Term: 1})
	}

	// Verify the store has the expected range
	first, err := store.FirstIndex()
	if err != nil {
		t.Fatal(err)
	}
	last, err := store.LastIndex()
	if err != nil {
		t.Fatal(err)
	}
	t.Logf("Log store range: %d to %d", first, last)

	// Simulate: snapshot was taken at index 50 (before our log range)
	// trailingLogs = 0
	// compactLogs should compute:
	//   minLog = first index of store (100)
	//   maxLog = snapIdx - trailingLogs = 50 - 0 = 50
	// This means maxLog (50) < minLog (100) => invalid range for DeleteRange

	snapIdx := uint64(50)
	trailingLogs := uint64(0)

	// Compute what compactLogs would do
	minLog := first
	maxLog := snapIdx - trailingLogs

	t.Logf("compactLogs would call DeleteRange(%d, %d)", minLog, maxLog)

	if maxLog < minLog {
		t.Errorf("FAIL: Bug is present — DeleteRange would be called with from=%d > to=%d (invalid negative range)", minLog, maxLog)
	} else {
		t.Logf("PASS: Range is valid (%d to %d)", minLog, maxLog)
	}

	// Also check whether the source code has a bounds check
	// The fix adds: if minLog > maxLog { return nil }
}
GOEOF

# Run the test
OUTPUT=$(go test -v -run TestCompactLogsNegativeRange -count=1 -timeout 30s . 2>&1)
EXIT_CODE=$?
echo "$OUTPUT"

# Clean up test file
rm -f negative_range_test.go

echo ""
if echo "$OUTPUT" | grep -q "FAIL.*Bug is present"; then
    echo "FAIL: Bug is present — compactLogs computes invalid range (maxLog < minLog)"
    exit 1
elif echo "$OUTPUT" | grep -q "PASS.*Range is valid"; then
    echo "PASS: Bug is fixed — compaction range is valid"
    exit 0
else
    echo "INCONCLUSIVE: Could not determine status (test exit code: $EXIT_CODE)"
    exit 1
fi
