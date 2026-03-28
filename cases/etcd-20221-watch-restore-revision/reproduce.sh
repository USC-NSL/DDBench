#!/usr/bin/env bash
# Reproduction and verification script for etcd-20221-watch-restore-revision
# Injects a regression test into the mvcc package that watches on a future
# revision, triggers a snapshot restore, and checks whether the watcher
# incorrectly receives events with revisions below its requested start.
# ── Docker mode (preferred) ──
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
    exec "$REPO_ROOT/bench.sh" reproduce "$CASE_NAME"
fi
# ── Host fallback (no Docker) ──
set -uo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/etcd-20221-watch-restore-revision"
TEST_FILE="$WORK_DIR/server/storage/mvcc/watchable_store_restore_bug_test.go"

export PATH="$PATH:/usr/local/go/bin"

# ── Rebuild if source changed ──
[ -f "$WORK_DIR/REBUILD.sh" ] && bash "$WORK_DIR/REBUILD.sh"

# Verify setup
if [ ! -d "$WORK_DIR" ]; then
    echo "ERROR: Work directory not found at $WORK_DIR. Run ./setup.sh first."
    exit 1
fi

echo "=== Reproducing etcd-20221-watch-restore-revision ==="

cleanup() {
    rm -f "$TEST_FILE"
}
trap cleanup EXIT

# Inject regression test into the mvcc package.
# This test follows the pattern from the fix PR (etcd/pull/20281).
# It uses existing test helpers (cleanup, readEventsForSecond) from
# watchable_store_test.go at the buggy commit.
cat > "$TEST_FILE" << 'GOEOF'
package mvcc

import (
	"testing"
	"time"

	"go.uber.org/zap/zaptest"

	"go.etcd.io/etcd/api/v3/mvccpb"
	"go.etcd.io/etcd/server/v3/lease"
	betesting "go.etcd.io/etcd/server/v3/storage/backend/testing"
)

// TestWatchRestoreFutureRevisionBug reproduces the bug described in
// https://github.com/etcd-io/etcd/issues/20221
//
// A watcher watching a future revision should NOT receive events with
// revisions below its start revision, even after a Restore().
func TestWatchRestoreFutureRevisionBug(t *testing.T) {
	b, _ := betesting.NewDefaultTmpBackend(t)
	s := New(zaptest.NewLogger(t), b, &lease.FakeLessor{}, StoreConfig{})
	defer cleanup(s, b)

	testKey := []byte("foo")
	testValue := []byte("bar")

	// Create a watcher at a future revision (startRev=4).
	// Current rev is 1 (empty store). Rev 4 is in the future.
	w := s.NewWatchStream()
	defer w.Close()
	w.Watch(0, testKey, nil, 4)

	// Write one key. Store advances to rev 2.
	s.Put(testKey, testValue, lease.NoLease) // rev 2

	// Let syncWatchersLoop run before restore to move the watcher
	// through the synced/unsynced groups.
	time.Sleep(500 * time.Millisecond)

	// Restore from the same backend. This moves ALL watchers
	// (including our future-revision watcher at startRev=4) to the
	// unsynced group. The store's current revision is still 2.
	s.Restore(b)

	// Let syncWatchersLoop run AFTER restore. This is where the bug
	// strikes: syncWatchers processes the unsynced watcher and sets
	//   BUGGY:  w.minRev = curRev + 1 = 3  (lowered from 4 to 3!)
	//   FIXED:  w.minRev = max(curRev+1, w.minRev) = max(3, 4) = 4
	time.Sleep(500 * time.Millisecond)

	// Delete the key. This creates revision 3.
	// On the buggy code: minRev was lowered to 3, so rev 3 >= 3 = true
	//   → the watcher incorrectly delivers this delete event.
	// On the fixed code: minRev is still 4, so rev 3 < 4 = false
	//   → the watcher correctly does NOT deliver this event.
	s.DeleteRange(testKey, nil) // rev 3

	// Collect events for the future-revision watcher.
	var events []mvccpb.Event
	deadline := time.After(2 * time.Second)
	for {
		select {
		case resp := <-w.Chan():
			events = append(events, resp.Events...)
		case <-deadline:
			goto done
		}
	}
done:

	// The watcher at startRev=4 should receive 0 events because the
	// only post-restore event is at rev 3, which is below startRev.
	if len(events) > 0 {
		t.Fatalf("Bug present: future-revision watcher (startRev=4) received %d event(s) "+
			"after restore. First event at revision %d, but watch starts at rev 4. "+
			"The watcher's minRev was incorrectly lowered during post-restore resync.",
			len(events), events[0].Kv.ModRevision)
	}
	t.Logf("OK: future-revision watcher correctly received 0 events after restore")
}
GOEOF

echo "Injected regression test: $TEST_FILE"
echo "Running go test in server/storage/mvcc..."

cd "$WORK_DIR/server"
OUTPUT=$(go test -v -run "^TestWatchRestoreFutureRevisionBug$" -count=1 -timeout 60s ./storage/mvcc/ 2>&1)
TEST_EXIT=$?
echo "$OUTPUT"

# Clean up the injected test
rm -f "$TEST_FILE"

echo ""
if [ "$TEST_EXIT" -ne 0 ]; then
    echo "FAIL: Bug is present — watch on future revision received events with revisions below the requested start after snapshot restore"
    exit 1
else
    echo "PASS: Bug is fixed — watch on future revision correctly withheld events below the requested start revision"
    exit 0
fi
