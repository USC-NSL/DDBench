#!/usr/bin/env bash
# Reproduction and verification script for etcd-20221-watch-restore-revision
# Injects a test into package server/storage/mvcc: a watcher on a future revision
# must not receive events below its start revision after the store is restored
# from a snapshot.
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

echo "=== Reproducing etcd-20221-watch-restore-revision ==="

ORACLE=TestDDBenchOracleWatchRestoreFutureRevision
ORACLE_FILE="$WORK_DIR/server/storage/mvcc/zz_ddbench_oracle_test.go"
cleanup() { rm -f "$ORACLE_FILE"; }
trap cleanup EXIT

cat > "$ORACLE_FILE" << 'GOEOF'
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
func TestDDBenchOracleWatchRestoreFutureRevision(t *testing.T) {
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

cd "$WORK_DIR/server"
echo "Running $ORACLE ..."
go_oracle "$ORACLE" ./storage/mvcc/ -timeout 60s
go_verdict "Bug is fixed — the future-revision watcher received no events below its start revision" \
           "Bug is present — the future-revision watcher received events below its start revision after restore"
