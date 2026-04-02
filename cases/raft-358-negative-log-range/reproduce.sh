#!/usr/bin/env bash
# Reproduction and verification script for raft-358-negative-log-range
# Writes a Go test that actually calls compactLogs with a spy LogStore
# and detects if DeleteRange is called with an invalid (min > max) range.
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

# Write behavioral test that actually calls compactLogs via a spy.
# The old approach only checked arithmetic (minLog/maxLog values) without
# invoking the implementation, so it always failed even with a correct fix.
# This test uses a spy LogStore to detect if DeleteRange is called with
# an invalid range (min > max) at runtime.
cat > negative_range_test.go <<'GOEOF'
package raft

import (
	"testing"

	"github.com/hashicorp/go-hclog"
)

// spyLogStore wraps InmemStore and records if DeleteRange is ever called
// with an invalid range where min > max.
type spyLogStore struct {
	*InmemStore
	invalidRangeCalled bool
	invalidMin         uint64
	invalidMax         uint64
}

func (s *spyLogStore) DeleteRange(mn, mx uint64) error {
	if mn > mx {
		s.invalidRangeCalled = true
		s.invalidMin = mn
		s.invalidMax = mx
	}
	return s.InmemStore.DeleteRange(mn, mx)
}

// TestCompactLogsNegativeRange exercises compactLogs with snapIdx=50, which is
// below the log store's first index (100). On buggy code this causes
// DeleteRange(100, 50) — an invalid call. A correct fix must prevent it.
func TestCompactLogsNegativeRange(t *testing.T) {
	// Populate in-memory log store with entries at indices 100-200.
	inner := NewInmemStore()
	for i := uint64(100); i <= 200; i++ {
		inner.StoreLog(&Log{Index: i, Term: 1})
	}
	first, _ := inner.FirstIndex()
	last, _ := inner.LastIndex()
	t.Logf("Log store range: %d to %d", first, last)

	spy := &spyLogStore{InmemStore: inner}

	// Build the minimal Raft needed by compactLogs:
	//   r.logs, r.conf.TrailingLogs, r.getLastLog(), r.logger
	r := &Raft{
		conf:   Config{TrailingLogs: 0},
		logs:   spy,
		logger: hclog.NewNullLogger(),
	}
	// setLastLog is promoted from the embedded raftState.
	// Set lastLogIndex=200 so snapIdx=50 is not clamped away.
	r.setLastLog(200, 1)

	// compactLogs(50) computes: maxLog = min(50, 200-0) = 50, minLog = 100.
	// Buggy code: DeleteRange(100, 50) — invalid. Fix: early return prevents it.
	snapIdx := uint64(50)
	t.Logf("Calling compactLogs(%d); log store first index is %d", snapIdx, first)

	_ = r.compactLogs(snapIdx)

	if spy.invalidRangeCalled {
		t.Errorf("FAIL: Bug is present — DeleteRange called with from=%d > to=%d (invalid negative range)",
			spy.invalidMin, spy.invalidMax)
	} else {
		t.Logf("PASS: Range is valid (compactLogs did not call DeleteRange with invalid args)")
	}
}
GOEOF

# Run the test
OUTPUT=$(go test -v -run TestCompactLogsNegativeRange -count=1 -timeout 30s . 2>&1)
EXIT_CODE=$?
echo "$OUTPUT"

# Clean up test file
rm -f negative_range_test.go

echo ""
# Build/compile failure: agent left conflicting files or broke the package.
# Treat as FAIL — a broken build means the bug is definitely not fixed.
if echo "$OUTPUT" | grep -qE "^(found packages|cannot find|build failed|# .*\[build failed\]|vet: )"; then
    echo "FAIL: Build error — agent left the codebase in a non-compilable state"
    exit 1
elif echo "$OUTPUT" | grep -q "FAIL.*Bug is present"; then
    echo "FAIL: Bug is present — compactLogs computes invalid range (maxLog < minLog)"
    exit 1
elif echo "$OUTPUT" | grep -q "PASS.*Range is valid"; then
    echo "PASS: Bug is fixed — compaction range is valid"
    exit 0
else
    echo "INCONCLUSIVE: Could not determine status (test exit code: $EXIT_CODE)"
    exit 1
fi
