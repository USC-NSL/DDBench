#!/usr/bin/env bash
# Reproduction and verification script for etcd-19179-watch-tombstone-compact
# Injects a regression test into the mvcc package that demonstrates the missing
# tombstone in the key index after restore. After compaction removes all put
# revisions for a key but keeps the tombstone, restoring the store from the
# backend fails to reconstruct the key index for that tombstone. A subsequent
# re-compaction then deletes the tombstone from bolt too, permanently losing
# the delete event.
# ── Docker mode (preferred) ──
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
    exec "$REPO_ROOT/bench.sh" reproduce "$CASE_NAME"
fi
# ── Host fallback (no Docker) ──
set -uo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/etcd-19179-watch-tombstone-compact"
TEST_FILE="$WORK_DIR/server/storage/mvcc/restore_tombstone_compact_bug_test.go"

export PATH="$PATH:/usr/local/go/bin"

# ── Rebuild if source changed ──
[ -f "$WORK_DIR/REBUILD.sh" ] && bash "$WORK_DIR/REBUILD.sh"

# Verify setup
if [ ! -d "$WORK_DIR" ]; then
    echo "ERROR: Work directory not found at $WORK_DIR. Run ./setup.sh first."
    exit 1
fi

echo "=== Reproducing etcd-19179-watch-tombstone-compact ==="

cleanup() {
    rm -f "$TEST_FILE"
}
trap cleanup EXIT

# Inject regression test into the mvcc package.
# This test follows the scenario from etcd issue #19179:
#   1. Put keys, delete one key, compact at the delete revision
#   2. Close and restore from backend (simulates restart)
#   3. After restore, check whether the key index contains an entry for the
#      deleted key's tombstone
#
# On the buggy code, restoreIntoIndex skips tombstones that are the only
# remaining revision for a key. The key index lacks the tombstone entry,
# so if compaction re-runs (as happens after a crash mid-compaction),
# the tombstone is deleted from bolt and the delete event is permanently lost.
cat > "$TEST_FILE" << 'GOEOF'
package mvcc

import (
	"testing"

	"go.uber.org/zap/zaptest"

	"go.etcd.io/etcd/pkg/v3/traceutil"
	"go.etcd.io/etcd/server/v3/lease"
	betesting "go.etcd.io/etcd/server/v3/storage/backend/testing"
)

// TestRestoreTombstoneAfterCompaction reproduces the bug described in
// https://github.com/etcd-io/etcd/issues/19179
//
// When a key's only remaining revision is a tombstone (all older revisions
// compacted away), the Restore() function fails to reconstruct the key
// index for that tombstone. If compaction is then re-run (as happens when
// etcd resumes an incomplete compaction after crash), the tombstone is
// deleted from bolt because it's not in the key index's "keep" set.
// The delete event is permanently lost.
func TestRestoreTombstoneAfterCompaction(t *testing.T) {
	compactBatchLimit := 5

	b, _ := betesting.NewDefaultTmpBackend(t)
	s := NewStore(zaptest.NewLogger(t), b, &lease.FakeLessor{}, StoreConfig{CompactionBatchLimit: compactBatchLimit})

	// Put 5 keys: foo1..foo5 (revisions 2..6)
	s.Put([]byte("foo1"), []byte("bar1"), 0) // rev 2
	s.Put([]byte("foo2"), []byte("bar2"), 0) // rev 3
	s.Put([]byte("foo3"), []byte("bar3"), 0) // rev 4
	s.Put([]byte("foo4"), []byte("bar4"), 0) // rev 5
	s.Put([]byte("foo5"), []byte("bar5"), 0) // rev 6

	// Delete foo1 -> creates tombstone at rev 7
	_, delAtRev := s.DeleteRange([]byte("foo1"), nil)
	if delAtRev != 7 {
		t.Fatalf("expected delete at rev 7, got %d", delAtRev)
	}

	// Compact at the delete revision. This removes foo1's put revision (2)
	// but keeps the tombstone at rev 7 in the database.
	ch, err := s.Compact(traceutil.TODO(), delAtRev)
	if err != nil {
		t.Fatalf("compact error: %v", err)
	}
	<-ch // wait for compaction to finish

	// Before close, verify the key index HAS an entry for foo1.
	// After compaction, foo1's key index should contain the tombstone
	// at rev 7 (and an empty current generation).
	kiBefore := s.kvindex.KeyIndex(&keyIndex{key: []byte("foo1")})
	if kiBefore == nil {
		t.Fatalf("foo1 should have a key index entry before close (with tombstone at rev %d)", delAtRev)
	}
	t.Logf("Before close: foo1 key index exists with tombstone at rev %d", delAtRev)

	// Close the store (simulates etcd shutdown / crash).
	s.Close()

	// Reopen from the same backend (simulates etcd restart).
	// This is where the bug strikes: restoreIntoIndex skips tombstones
	// that are the only remaining revision for a key.
	ns := NewStore(zaptest.NewLogger(t), b, &lease.FakeLessor{}, StoreConfig{CompactionBatchLimit: compactBatchLimit})

	// After restore, check if the key index has an entry for foo1.
	// On the buggy code, foo1 has no key index entry because its tombstone
	// was skipped during restoreIntoIndex.
	kiAfter := ns.kvindex.KeyIndex(&keyIndex{key: []byte("foo1")})

	ns.Close()
	b.Close()

	if kiAfter == nil {
		t.Fatalf("Bug present — foo1 has NO key index entry after restore. "+
			"The tombstone at rev %d was not reconstructed during restoreIntoIndex. "+
			"If compaction resumes after a crash, this tombstone will be permanently deleted "+
			"from the database, causing the delete event to be lost on watches.", delAtRev)
	}

	t.Logf("OK: foo1 key index correctly restored with tombstone at rev %d", delAtRev)
}
GOEOF

echo "Injected regression test: $TEST_FILE"
echo "Running go test in server/storage/mvcc..."

cd "$WORK_DIR/server"
OUTPUT=$(go test -v -run "^TestRestoreTombstoneAfterCompaction$" -count=1 -timeout 120s ./storage/mvcc/ 2>&1)
TEST_EXIT=$?
echo "$OUTPUT"

# Clean up the injected test
rm -f "$TEST_FILE"

echo ""
if [ "$TEST_EXIT" -ne 0 ]; then
    echo "FAIL: Bug is present — tombstone not restored after compaction; delete event lost on restart"
    exit 1
else
    echo "PASS: Bug is fixed — tombstone correctly restored after compaction and restart"
    exit 0
fi
