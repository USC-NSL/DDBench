#!/usr/bin/env bash
# Reproduction and verification script for consul-9772-streaming-snapshot-cache
# Injects a test into package agent/consul/stream that exercises the snapshot
# cache after a stale-index resume, then checks that a fresh subscriber
# (Index=0) gets the snapshot data first and no newSnapshotToFollow framing event.
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

ORACLE="TestDDBenchOracleSnapshotCacheFreshSubscriber"
ORACLE_FILE="$WORK_DIR/agent/consul/stream/zz_ddbench_oracle_test.go"


rebuild_worktree
[ -d "$WORK_DIR/agent/consul/stream" ] || error "package agent/consul/stream not found in $WORK_DIR (run setup first)"
cd "$WORK_DIR"

echo "=== Reproducing consul-9772-streaming-snapshot-cache ==="

cleanup() { rm -f "$ORACLE_FILE"; }
trap cleanup EXIT

# The oracle test is always injected fresh, under a ddbench-only name and file,
# so a same-named test in the worktree can neither replace nor collide with it.
cat > "$ORACLE_FILE" << 'TESTEOF'
package stream

import (
	"context"
	"fmt"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)
func TestDDBenchOracleSnapshotCacheFreshSubscriber(t *testing.T) {
	req := &SubscribeRequest{
		Topic: testTopic,
		Key:   "sub-key",
		Index: 1,
	}

	nextEvent := Event{
		Topic:   testTopic,
		Index:   3,
		Payload: simplePayload{key: "sub-key", value: "event-3"},
	}

	handlers := SnapshotHandlers{
		testTopic: func(req SubscribeRequest, buf SnapshotAppender) (uint64, error) {
			if req.Topic != testTopic {
				return 0, fmt.Errorf("unexpected topic: %v", req.Topic)
			}
			buf.Append([]Event{testSnapshotEvent})
			buf.Append([]Event{nextEvent})
			return 3, nil
		},
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	publisher := NewEventPublisher(handlers, time.Second)
	go publisher.Run(ctx)
	// Include the same events in the topicBuffer
	publisher.publishEvent([]Event{testSnapshotEvent})
	publisher.publishEvent([]Event{nextEvent})

	runStep(t, "start a subscription and unsub", func(t *testing.T) {
		sub, err := publisher.Subscribe(req)
		require.NoError(t, err)
		defer sub.Unsubscribe()

		eventCh := runSubscription(ctx, sub)
		next := getNextEvent(t, eventCh)
		require.True(t, next.IsNewSnapshotToFollow(),
			"expected newSnapshotToFollow, got: %v", next)

		next = getNextEvent(t, eventCh)
		require.Equal(t, testSnapshotEvent, next)

		next = getNextEvent(t, eventCh)
		require.Equal(t, nextEvent, next)

		next = getNextEvent(t, eventCh)
		require.True(t, next.IsEndOfSnapshot(),
			"expected endOfSnapshot, got: %v", next)
		require.Equal(t, uint64(3), next.Index)
	})

	publisher.snapshotHandlers[testTopic] = func(_ SubscribeRequest, _ SnapshotAppender) (uint64, error) {
		return 0, fmt.Errorf("error should not be seen, cache should have been used")
	}

	runStep(t, "resume the subscription", func(t *testing.T) {
		newReq := *req
		newReq.Index = 0
		sub, err := publisher.Subscribe(&newReq)
		require.NoError(t, err)

		eventCh := runSubscription(ctx, sub)
		next := getNextEvent(t, eventCh)
		require.Equal(t, testSnapshotEvent, next,
			"fresh subscriber (Index=0) should get snapshot data first, not a framing event")

		next = getNextEvent(t, eventCh)
		require.Equal(t, nextEvent, next)

		next = getNextEvent(t, eventCh)
		require.True(t, next.IsEndOfSnapshot())
	})
}
TESTEOF

echo "Running $ORACLE ..."
go_oracle "$ORACLE" ./agent/consul/stream/ -timeout 60s
go_verdict "Bug is fixed — a fresh subscriber receives snapshot data first" \
           "Bug is present — a fresh subscriber received the cached newSnapshotToFollow framing event"
