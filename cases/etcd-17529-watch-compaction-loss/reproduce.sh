#!/usr/bin/env bash
# Reproduction and verification script for etcd-17529-watch-compaction-loss
# Injects a test into package server/storage/mvcc: with a tiny watch channel buffer,
# every watcher whose start revision was compacted must eventually receive a
# compaction response.
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

echo "=== Reproducing etcd-17529-watch-compaction-loss ==="

ORACLE=TestDDBenchOracleWatchCompactionNotified
ORACLE_FILE="$WORK_DIR/server/storage/mvcc/zz_ddbench_oracle_test.go"
cleanup() { rm -f "$ORACLE_FILE"; }
trap cleanup EXIT

cat > "$ORACLE_FILE" << 'GOEOF'
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
func TestDDBenchOracleWatchCompactionNotified(t *testing.T) {
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

cd "$WORK_DIR/server"
echo "Running $ORACLE ..."
go_oracle "$ORACLE" ./storage/mvcc/ -timeout 120s
go_verdict "Bug is fixed — all compacted watchers receive their compaction notification" \
           "Bug is present — some compacted watchers never received a compaction notification"
