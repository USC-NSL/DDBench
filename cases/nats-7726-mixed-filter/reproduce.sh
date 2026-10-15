#!/usr/bin/env bash
# Reproduction and verification script for nats-7726-mixed-filter
# Injects a JetStream test into package server that reproduces the reported
# scenario: a pull consumer whose filter subjects mix partial-wildcard patterns
# with a literal subject must deliver a message published to the literal subject,
# even when the stream already holds non-matching messages that share the
# literal's prefix. Checked for file and memory storage.
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

ORACLE_FILE="$WORK_DIR/server/zz_ddbench_oracle_test.go"


rebuild_worktree
[ -x "$WORK_DIR/nats-server" ] || error "nats-server binary not found in $WORK_DIR (run setup first)"
cd "$WORK_DIR"

echo "=== Reproducing nats-7726-mixed-filter ==="

cleanup() { rm -f "$ORACLE_FILE"; }
trap cleanup EXIT

# The oracle test is always injected fresh, under a ddbench-only name and file,
# so a same-named test in the worktree can neither replace nor collide with it.
cat > "$ORACLE_FILE" << 'TESTEOF'
package server

import (
	"testing"
	"time"

	"github.com/nats-io/nats.go"
)

func TestDDBenchOracleMixedFilterLiteralDelivery(t *testing.T) {
	for _, st := range []nats.StorageType{nats.FileStorage, nats.MemoryStorage} {
		t.Run(st.String(), func(t *testing.T) {
			s := RunBasicJetStreamServer(t)
			defer s.Shutdown()

			nc, js := jsClientConnect(t, s)
			defer nc.Close()

			_, err := js.AddStream(&nats.StreamConfig{
				Name:     "EVENTS",
				Subjects: []string{"events.>"},
				Storage:  st,
			})
			require_NoError(t, err)

			_, err = js.AddConsumer("EVENTS", &nats.ConsumerConfig{
				Durable:       "MIXED",
				AckPolicy:     nats.AckExplicitPolicy,
				DeliverPolicy: nats.DeliverAllPolicy,
				FilterSubjects: []string{
					"events.*.datastore.batch.access.modified",
					"events.*.processor.complete.batch.inserted",
					"events.main.datastore.result.created",
				},
			})
			require_NoError(t, err)

			// Non-matching messages that share the literal filter's prefix.
			for _, subj := range []string{
				"events.main.datastore.record.created",
				"events.main.datastore.group.created",
				"events.main.datastore.batch.created",
				"events.main.datastore.items.created",
				"events.main.datastore.items.created",
				"events.main.datastore.items.created",
				"events.main.datastore.items.created",
			} {
				_, err = js.Publish(subj, []byte("other"))
				require_NoError(t, err)
			}
			_, err = js.Publish("events.main.datastore.result.created", []byte("expected"))
			require_NoError(t, err)

			si, err := js.StreamInfo("EVENTS")
			require_NoError(t, err)
			require_Equal(t, si.State.Msgs, uint64(8))

			sub, err := js.PullSubscribe(_EMPTY_, "MIXED", nats.Bind("EVENTS", "MIXED"))
			require_NoError(t, err)
			defer sub.Unsubscribe()

			msgs, err := sub.Fetch(1, nats.MaxWait(3*time.Second))
			if err != nil {
				t.Fatalf("message on the literal filter subject was not delivered: %v", err)
			}
			require_Len(t, len(msgs), 1)
			require_Equal(t, msgs[0].Subject, "events.main.datastore.result.created")
			require_Equal(t, string(msgs[0].Data), "expected")
		})
	}
}
TESTEOF

echo "Running TestDDBenchOracleMixedFilterLiteralDelivery ..."
go_oracle TestDDBenchOracleMixedFilterLiteralDelivery ./server/ -timeout 120s
go_verdict "Bug is fixed — the consumer delivers the message on its literal filter subject" \
           "Bug is present — a message on the consumer's literal filter subject was never delivered"
