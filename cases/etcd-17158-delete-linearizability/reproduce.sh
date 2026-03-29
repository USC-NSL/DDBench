#!/usr/bin/env bash
# Reproduction and verification script for etcd-17158-delete-linearizability
# Injects a regression test into the backend package that puts a key, commits,
# deletes the key, then reads via both BatchTx and ReadTx. On the buggy commit,
# ReadTx still returns the deleted key because the delete bypasses the read buffer
# and the bbolt transaction is not committed immediately.
# ── Docker mode (preferred) ──
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
    exec "$REPO_ROOT/bench.sh" reproduce "$CASE_NAME"
fi
# ── Host fallback (no Docker) ──
set -uo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/etcd-17158-delete-linearizability"
TEST_FILE="$WORK_DIR/server/storage/backend/delete_linearizability_bug_test.go"

export PATH="$PATH:/usr/local/go/bin"

# ── Rebuild if source changed ──
[ -f "$WORK_DIR/REBUILD.sh" ] && bash "$WORK_DIR/REBUILD.sh"

# Verify setup
if [ ! -d "$WORK_DIR" ]; then
    echo "ERROR: Work directory not found at $WORK_DIR. Run ./setup.sh first."
    exit 1
fi

echo "=== Reproducing etcd-17158-delete-linearizability ==="

INJECTED=false
cleanup() {
    [ "$INJECTED" = true ] && rm -f "$TEST_FILE"
}
trap cleanup EXIT

# Inject regression test into the backend package (skip if fix commit already includes it).
# This test follows the pattern from the fix PR (etcd/pull/17195).
# It uses the exported Backend, BatchTx, and ReadTx interfaces, which are
# accessible from the backend_test package. The test creates a backend with
# a long batch interval so automatic commits never fire, then demonstrates
# that a delete followed by a read returns inconsistent results.
TEST_NAME="TestRangeAfterDeleteMatch"
if grep -rq "func ${TEST_NAME}" "$WORK_DIR/server/storage/backend/"*_test.go 2>/dev/null; then
    echo "Test $TEST_NAME already exists in source (fix commit) — skipping injection"
else
    INJECTED=true
    cat > "$TEST_FILE" << 'GOEOF'
package backend_test

import (
	"reflect"
	"testing"
	"time"

	betesting "go.etcd.io/etcd/server/v3/storage/backend/testing"
	"go.etcd.io/etcd/server/v3/storage/schema"
)

// TestRangeAfterDeleteMatch reproduces the bug described in
// https://github.com/etcd-io/etcd/issues/17158
//
// etcd uses a buffered batch transaction on top of bbolt. Put operations
// are buffered: reads check both bbolt and the in-memory buffer. But
// delete operations have no equivalent buffer handling. When a key is
// deleted, the delete only modifies the pending bbolt transaction. On
// Unlock(), the stale buffer (still containing the put) is written back
// to the read transaction buffer. If the bbolt transaction hasn't been
// committed yet (pending < batchLimit), a subsequent read via ReadTx
// sees the deleted key in the stale buffer and returns it.
//
// The fix (etcd/pull/17195) forces an immediate bbolt commit when there
// are pending delete operations, ensuring the read path reflects deletions.
func TestRangeAfterDeleteMatch(t *testing.T) {
	// Use a long batch interval and high batch limit so automatic commits
	// never trigger during this test. This isolates the delete buffering bug.
	b, _ := betesting.NewTmpBackend(t, time.Hour, 10000)
	defer betesting.Close(t, b)

	tx := b.BatchTx()

	// Step 1: Put a key and commit so it's persisted in both bbolt and the buffer.
	tx.Lock()
	tx.UnsafeCreateBucket(schema.Test)
	tx.UnsafePut(schema.Test, []byte("foo"), []byte("bar"))
	tx.Unlock()
	tx.Commit()

	// Sanity check: both BatchTx and ReadTx should see the key.
	tx.Lock()
	ks1, vs1 := tx.UnsafeRange(schema.Test, []byte("foo"), nil, 0)
	tx.Unlock()

	rtx := b.ReadTx()
	rtx.RLock()
	ks2, vs2 := rtx.UnsafeRange(schema.Test, []byte("foo"), nil, 0)
	rtx.RUnlock()

	if len(ks1) != 1 || len(ks2) != 1 {
		t.Fatalf("sanity check failed: expected key 'foo' to exist in both BatchTx and ReadTx before delete")
	}
	if !reflect.DeepEqual(ks1, ks2) || !reflect.DeepEqual(vs1, vs2) {
		t.Fatalf("sanity check failed: BatchTx and ReadTx disagree before delete")
	}

	// Step 2: Delete the key. No explicit commit -- the bug is that
	// Unlock() does not force a commit for deletes, leaving the read
	// buffer stale.
	tx.Lock()
	tx.UnsafeDelete(schema.Test, []byte("foo"))
	tx.Unlock()

	// Step 3: Read the key via both BatchTx and ReadTx.
	// After the delete, both should return empty results.
	tx.Lock()
	ksAfterBatch, _ := tx.UnsafeRange(schema.Test, []byte("foo"), nil, 0)
	tx.Unlock()

	rtx.RLock()
	ksAfterRead, _ := rtx.UnsafeRange(schema.Test, []byte("foo"), nil, 0)
	rtx.RUnlock()

	// On the buggy code:
	//   - BatchTx returns [] (correct: sees the pending delete in bbolt)
	//   - ReadTx returns [foo] (wrong: reads from stale buffer)
	//
	// On the fixed code:
	//   - Both return [] (the fix forces a bbolt commit on delete,
	//     so the read path no longer sees the stale buffer entry)
	if !reflect.DeepEqual(ksAfterBatch, ksAfterRead) {
		t.Errorf("FAIL: BatchTx and ReadTx disagree after delete\n"+
			"  BatchTx keys: %v (correct)\n"+
			"  ReadTx keys:  %v (stale -- delete not reflected in read buffer)\n"+
			"This is the linearizability violation described in etcd#17158:\n"+
			"  UnsafeDelete bypasses the read buffer, so a read after delete\n"+
			"  returns the deleted key from the stale buffer.",
			formatKeys(ksAfterBatch), formatKeys(ksAfterRead))
	}

	// Also verify via ForEach that the key is gone from both paths.
	var batchKeys, readKeys [][]byte

	tx.Lock()
	tx.UnsafeForEach(schema.Test, func(k, v []byte) error {
		batchKeys = append(batchKeys, k)
		return nil
	})
	tx.Unlock()

	rtx.RLock()
	rtx.UnsafeForEach(schema.Test, func(k, v []byte) error {
		readKeys = append(readKeys, k)
		return nil
	})
	rtx.RUnlock()

	if !reflect.DeepEqual(batchKeys, readKeys) {
		t.Errorf("FAIL: ForEach inconsistency after delete\n"+
			"  BatchTx ForEach keys: %v\n"+
			"  ReadTx ForEach keys:  %v",
			formatKeys(batchKeys), formatKeys(readKeys))
	}

	if len(ksAfterRead) > 0 || len(readKeys) > 0 {
		t.Fatalf("FAIL: Bug is present -- deleted key still visible via ReadTx, "+
			"violating linearizability (etcd#17158)")
	}

	t.Log("OK: deleted key is correctly invisible via both BatchTx and ReadTx")
}

func formatKeys(keys [][]byte) []string {
	var result []string
	for _, k := range keys {
		result = append(result, string(k))
	}
	return result
}
GOEOF
    echo "Injected regression test: $TEST_FILE"
fi

echo "Running go test in server/storage/backend..."

cd "$WORK_DIR/server"
OUTPUT=$(go test -v -run "^${TEST_NAME}$" -count=1 -timeout 60s ./storage/backend/ 2>&1)
TEST_EXIT=$?
echo "$OUTPUT"

echo ""
if [ "$TEST_EXIT" -ne 0 ]; then
    echo "FAIL: Bug is present -- UnsafeDelete bypasses the read buffer, causing stale reads that violate linearizability"
    exit 1
else
    echo "PASS: Bug is fixed -- delete operations are correctly reflected in the read path"
    exit 0
fi
