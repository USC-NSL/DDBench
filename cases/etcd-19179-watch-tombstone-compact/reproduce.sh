#!/usr/bin/env bash
# Reproduction and verification script for etcd-19179-watch-tombstone-compact
# Injects a test into package server/storage/mvcc: put keys, delete one, compact at
# the delete revision, restore the store from the backend, and check that the
# deleted key's tombstone is still indexed.
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

echo "=== Reproducing etcd-19179-watch-tombstone-compact ==="

ORACLE=TestDDBenchOracleRestoreTombstoneAfterCompaction
ORACLE_FILE="$WORK_DIR/server/storage/mvcc/zz_ddbench_oracle_test.go"
cleanup() { rm -f "$ORACLE_FILE"; }
trap cleanup EXIT

cat > "$ORACLE_FILE" << 'GOEOF'
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
func TestDDBenchOracleRestoreTombstoneAfterCompaction(t *testing.T) {
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

cd "$WORK_DIR/server"
echo "Running $ORACLE ..."
go_oracle "$ORACLE" ./storage/mvcc/ -timeout 120s
go_verdict "Bug is fixed — the tombstone is restored after compaction and restart" \
           "Bug is present — the tombstone is missing from the index after restore"
