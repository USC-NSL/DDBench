#!/usr/bin/env bash
# Reproduction and verification script for etcd-17529-watch-compaction-loss
# Injects a regression test into the mvcc package that creates watchers with
# revisions below a compaction point, forces channel congestion so one
# watcher's compaction notification is dropped, and verifies the watcher
# eventually receives the compaction response on retry.
# ── Docker mode (preferred) ──
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
    exec "$REPO_ROOT/bench.sh" reproduce "$CASE_NAME"
fi
# ── Host fallback (no Docker) ──
set -uo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/etcd-17529-watch-compaction-loss"
TEST_FILE="$WORK_DIR/server/storage/mvcc/watch_compaction_loss_bug_test.go"

export PATH="$PATH:/usr/local/go/bin"

# ── Rebuild if source changed ──
[ -f "$WORK_DIR/REBUILD.sh" ] && bash "$WORK_DIR/REBUILD.sh"

# Verify setup
if [ ! -d "$WORK_DIR" ]; then
    echo "ERROR: Work directory not found at $WORK_DIR. Run ./setup.sh first."
    exit 1
fi

echo "=== Reproducing etcd-17529-watch-compaction-loss ==="

cleanup() {
    rm -f "$TEST_FILE"
}
trap cleanup EXIT

# Inject regression test into the mvcc package.
# This test follows the pattern from the fix PR (etcd/pull/17555).
# It uses internal package-level vars (chanBufLen, maxWatchersPerSync) and
# the private syncWatchers() method, which are accessible because the test
# file is in package mvcc.
cat > "$TEST_FILE" << 'GOEOF'
package mvcc

import (
	"fmt"
	"testing"
	"time"

	"go.uber.org/zap/zaptest"

	"go.etcd.io/etcd/pkg/v3/traceutil"
	"go.etcd.io/etcd/server/v3/lease"
	betesting "go.etcd.io/etcd/server/v3/storage/backend/testing"
)

// TestWatchNoEventLossOnCompactBug reproduces the bug described in
// https://github.com/etcd-io/etcd/issues/17529
//
// Bug mechanism: syncWatchers() calls chooseAll() which tries to send
// compaction notifications via non-blocking select on w.ch. When the
// channel buffer is full, the send silently fails. However, syncWatchers()
// still unconditionally advances w.minRev = curRev+1 for ALL watchers in
// the batch, including those whose compaction send failed. On the next
// sync round, w.minRev > compactRev, so the compaction is never retried.
//
// The test uses chanBufLen=1 and creates multiple compacted watchers so
// that at least one watcher's compaction notification is guaranteed to be
// dropped. It then verifies ALL compacted watchers eventually receive
// their compaction response.
func TestWatchNoEventLossOnCompactBug(t *testing.T) {
	oldChanBufLen, oldMaxWatchersPerSync := chanBufLen, maxWatchersPerSync

	b, _ := betesting.NewDefaultTmpBackend(t)
	lg := zaptest.NewLogger(t)

	// Set chanBufLen BEFORE creating the store, because NewWatchStream()
	// uses it to size the channel.
	chanBufLen, maxWatchersPerSync = 1, 8

	s := newWatchableStore(lg, b, &lease.FakeLessor{}, StoreConfig{})

	defer func() {
		cleanup(s, b)
		chanBufLen, maxWatchersPerSync = oldChanBufLen, oldMaxWatchersPerSync
	}()

	testKey, testValue := []byte("foo"), []byte("bar")

	maxRev := 10
	compactRev := int64(5)
	for i := 0; i < maxRev; i++ {
		s.Put(testKey, testValue, lease.NoLease)
	}
	_, err := s.Compact(traceutil.TODO(), compactRev)
	if err != nil {
		t.Fatalf("failed to compact kv: %v", err)
	}

	w := s.NewWatchStream()
	defer w.Close()

	// Create 5 watchers:
	//   WatchID 0-3: startRev=1 (below compaction) -> must get compaction notification
	//   WatchID 4:   startRev=6 (above compaction) -> gets events 6..10
	//
	// With chanBufLen=1, only ONE compaction notification can be buffered
	// per syncWatchers() call. The other 3 will fail silently.
	// On buggy code, those 3 get advanced to curRev+1 and never retried.
	type watcherExpect struct {
		startRev        int64
		wantCompactResp bool
	}
	watchers := []watcherExpect{
		{startRev: 1, wantCompactResp: true},
		{startRev: 1, wantCompactResp: true},
		{startRev: 1, wantCompactResp: true},
		{startRev: 1, wantCompactResp: true},
		{startRev: 6, wantCompactResp: false},
	}
	for id, we := range watchers {
		_, err := w.Watch(WatchID(id), testKey, nil, we.startRev)
		if err != nil {
			t.Fatalf("failed to create watcher %d: %v", id, err)
		}
	}

	// Call syncWatchers() repeatedly. Between calls, drain the channel
	// so the buffer is free for the next retry. On fixed code, each
	// round retries the failed compaction sends. On buggy code, the
	// watchers have already been advanced past compactRev so retries
	// never happen.
	gotCompact := make(map[WatchID]bool)

	for round := 0; round < 30; round++ {
		s.syncWatchers()

		// Drain all available responses
		for {
			select {
			case resp := <-w.Chan():
				if resp.CompactRevision != 0 {
					gotCompact[resp.WatchID] = true
				}
			default:
				goto drained
			}
		}
	drained:
		time.Sleep(5 * time.Millisecond)
	}

	// Verify: ALL compacted watchers must have received notifications.
	var failures []string
	for id, we := range watchers {
		if we.wantCompactResp {
			if !gotCompact[WatchID(id)] {
				failures = append(failures, fmt.Sprintf(
					"watcher %d (startRev=%d): expected CompactRevision=%d but never received — "+
						"silently advanced past compaction point",
					id, we.startRev, compactRev))
			}
		}
	}

	if len(failures) > 0 {
		for _, f := range failures {
			t.Log(f)
		}
		t.Fatalf("FAIL: %d watcher(s) never received compaction notification — "+
			"watch event loss after compaction", len(failures))
	}

	t.Log("OK: all compacted watchers received compaction notifications")
}
GOEOF

echo "Injected regression test: $TEST_FILE"
echo "Running go test in server/storage/mvcc..."

cd "$WORK_DIR/server"
OUTPUT=$(go test -v -run "^TestWatchNoEventLossOnCompactBug$" -count=1 -timeout 120s ./storage/mvcc/ 2>&1)
TEST_EXIT=$?
echo "$OUTPUT"

# Clean up the injected test
rm -f "$TEST_FILE"

echo ""
if [ "$TEST_EXIT" -ne 0 ]; then
    echo "FAIL: Bug is present — watch compaction notification lost when channel buffer is full, watcher silently advanced past compacted range"
    exit 1
else
    echo "PASS: Bug is fixed — all compacted watchers eventually receive their compaction notifications"
    exit 0
fi
