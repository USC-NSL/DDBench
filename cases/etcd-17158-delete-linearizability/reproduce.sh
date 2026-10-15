#!/usr/bin/env bash
# Reproduction and verification script for etcd-17158-delete-linearizability
# Injects a test into server/storage/backend (package backend_test): after a key is
# deleted through a batch transaction, reads through BatchTx and ReadTx must agree
# that it is gone.
#
# Exit codes: 0 = PASS (bug fixed), 1 = FAIL (bug present, or the worktree does
# not build / the code under test does not start), 2 = ERROR (oracle or
# infrastructure problem; the verdict is inconclusive).
# ── Runs only inside the bench.sh reproduce container (BENCH_WORKDIR is set) ──
if [ -z "${BENCH_WORKDIR:-}" ]; then
    CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
    REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    [ -f "$REPO_ROOT/bench.sh" ] && exec bash "$REPO_ROOT/bench.sh" reproduce "$CASE_NAME"
    echo "ERROR: run this oracle with ./bench.sh reproduce $CASE_NAME" >&2
    exit 2
fi
set -uo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$BENCH_WORKDIR"
RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ddbench.XXXXXX")"   # scratch space outside the worktree

pass()  { echo ""; echo "PASS: $*"; exit 0; }
fail()  { echo ""; echo "FAIL: $*"; exit 1; }
error() { echo ""; echo "ERROR: $*"; exit 2; }

# REBUILD.sh is the worktree's designated build entry point.
rebuild_worktree() {
    [ -f "$WORK_DIR/REBUILD.sh" ] || error "REBUILD.sh not found in $WORK_DIR (run setup first)"
    bash "$WORK_DIR/REBUILD.sh" || fail "the worktree does not build (REBUILD.sh exited non-zero)"
}

# ── Go test verdicts ──
# Decided from `go test -json` events for the exact oracle test, never from free
# text (code under test can print anything). A test that did not run is no pass.
go_test_result() {  # <json-log> <TestName> -> pass | fail | skip | norun
    local pre='^\{("Time":"[^"]*",)?"Action":"' post="\",\"Package\":\"[^\"]*\",\"Test\":\"$2\"[,}]"
    if   grep -qE "${pre}fail${post}" "$1"; then echo fail
    elif grep -qE "${pre}pass${post}" "$1"; then echo pass
    elif grep -qE "${pre}skip${post}" "$1"; then echo skip
    else echo norun; fi
}
go_test_transcript() {  # human-readable form of a -json log
    sed -n -e '/^{/!p' -e 's/^{.*"Action":"output".*"Output":"\(.*\)"}$/\1/p' "$1" \
        | sed -e 's/\\n$//' -e 's/\\t/	/g' -e 's/\\"/"/g' -e 's/\\u003c/</g' \
              -e 's/\\u003e/>/g' -e 's/\\u0026/\&/g' -e 's/\\\\/\\/g'
}
# go_oracle <TestName> <package> [go test flags...]: run exactly one test from
# the current directory. Sets GO_RESULT (pass|fail|skip|norun) and GO_LOG.
go_oracle() {
    local name="$1" pkg="$2"; shift 2
    GO_LOG="$RUN_DIR/go-test-$name-$RANDOM.json"
    go test -json -count=1 -run "^${name}\$" "$@" "$pkg" > "$GO_LOG" 2>&1
    go_test_transcript "$GO_LOG" | tail -n 40
    GO_RESULT=$(go_test_result "$GO_LOG" "$name")
}
# Verdict when the oracle test produced no result.
go_norun_verdict() {  # <json-log>
    if grep -qE 'dial tcp|i/o timeout|TLS handshake timeout|no such host|connection reset by peer' "$1" \
       && ! grep -qE '\.go:[0-9]+:[0-9]+: ' "$1"; then
        error "the oracle test did not run: Go module download failed (network)"
    fi
    fail "the oracle test did not run (the package or the injected oracle test does not compile)"
}
# Exit with the verdict for GO_RESULT.
go_verdict() {  # <pass-message> <fail-message>
    case "$GO_RESULT" in
        pass) pass "$1" ;;
        fail) fail "$2" ;;
        skip) fail "the oracle test was skipped" ;;
        *)    go_norun_verdict "$GO_LOG" ;;
    esac
}


rebuild_worktree
[ -d "$WORK_DIR/server" ] || error "etcd source not found in $WORK_DIR (run setup first)"

echo "=== Reproducing etcd-17158-delete-linearizability ==="

ORACLE=TestDDBenchOracleRangeAfterDelete
ORACLE_FILE="$WORK_DIR/server/storage/backend/zz_ddbench_oracle_test.go"
cleanup() { rm -f "$ORACLE_FILE"; }
trap cleanup EXIT

# Always inject fresh, under a ddbench-only name and file (never skipped).
cat > "$ORACLE_FILE" << 'GOEOF'
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
func TestDDBenchOracleRangeAfterDelete(t *testing.T) {
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
			ddbenchFormatKeys(ksAfterBatch), ddbenchFormatKeys(ksAfterRead))
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
			ddbenchFormatKeys(batchKeys), ddbenchFormatKeys(readKeys))
	}

	if len(ksAfterRead) > 0 || len(readKeys) > 0 {
		t.Fatalf("FAIL: Bug is present -- deleted key still visible via ReadTx, "+
			"violating linearizability (etcd#17158)")
	}

	t.Log("OK: deleted key is correctly invisible via both BatchTx and ReadTx")
}

func ddbenchFormatKeys(keys [][]byte) []string {
	var result []string
	for _, k := range keys {
		result = append(result, string(k))
	}
	return result
}
GOEOF

cd "$WORK_DIR/server"
echo "Running $ORACLE ..."
go_oracle "$ORACLE" ./storage/backend/ -timeout 60s
go_verdict "Bug is fixed — delete operations are reflected in the read path" \
           "Bug is present — a deleted key is still visible through ReadTx"
