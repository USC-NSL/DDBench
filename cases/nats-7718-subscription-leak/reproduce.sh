#!/usr/bin/env bash
# Reproduction and verification script for nats-7718-subscription-leak
# Injects a clustered JetStream test into package server: with an account that
# imports a stream overlapping the JetStream API subjects, repeated stream and
# consumer create/delete cycles must leave the subscription count unchanged.
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

echo "=== Reproducing nats-7718-subscription-leak ==="

cleanup() { rm -f "$ORACLE_FILE"; }
trap cleanup EXIT

# The oracle test is always injected fresh, under a ddbench-only name and file,
# so a same-named test in the worktree can neither replace nor collide with it.
cat > "$ORACLE_FILE" << 'TESTEOF'
package server

import (
	"fmt"
	"testing"
	"time"

	"github.com/nats-io/nats.go"
)
func TestDDBenchOracleLeakedSubsStreamImportOverlap(t *testing.T) {
	tmpl := `
	listen: 127.0.0.1:-1
	server_name: %s
	jetstream: {max_mem_store: 2GB, max_file_store: 2GB, store_dir: '%s'}

	leaf {
		listen: 127.0.0.1:-1
	}

	cluster {
		name: %s
		listen: 127.0.0.1:%d
		routes = [%s]
	}

	accounts {
	  ACC: {
		jetstream: enabled
		users: [{user: acc, password: acc}]
		imports: [{stream: {account: zone, subject: ">"}}]
	  }
	  zone: {
		jetstream: enabled
		users: [{user: zone, password: zone}]
		exports: [{stream: ">"}]
	  }
	}
	no_auth_user: acc
`
	c := createJetStreamClusterWithTemplate(t, tmpl, "R3S", 3)
	defer c.shutdown()

	nc, js := jsClientConnect(t, c.randomServer())
	defer nc.Close()

	checkExpectedSubs := func(expected uint32) (actual uint32) {
		t.Helper()
		checkFor(t, 2*time.Second, 100*time.Millisecond, func() error {
			e := expected
			for _, s := range c.servers {
				subs := s.NumSubscriptions()
				if e == 0 {
					e = subs
				} else if e != subs {
					return fmt.Errorf("expected %d subs, got %d", e, subs)
				}
			}
			actual = e
			return nil
		})
		return actual
	}

	var baseline, sc, cc uint32

	for range 3 {
		initial := checkExpectedSubs(0)

		if baseline != 0 {
			require_Equal(t, baseline, initial)
		}

		_, err := js.AddStream(&nats.StreamConfig{
			Name:     "TEST",
			Subjects: []string{"foo"},
			Replicas: 1,
			Storage:  nats.FileStorage,
		})
		require_NoError(t, err)
		sl := c.streamLeader("ACC", "TEST")
		require_NotNil(t, sl)
		afterStreamCreate := checkExpectedSubs(sl.NumSubscriptions())
		if sc == 0 {
			sc = afterStreamCreate
		}
		require_Equal(t, sc, afterStreamCreate)

		_, err = js.AddConsumer("TEST", &nats.ConsumerConfig{Durable: "CONSUMER"})
		require_NoError(t, err)
		afterConsumerCreate := checkExpectedSubs(sl.NumSubscriptions())
		if cc == 0 {
			cc = afterConsumerCreate
		}
		require_Equal(t, cc, afterConsumerCreate)

		require_NoError(t, js.DeleteConsumer("TEST", "CONSUMER"))
		afterConsumerDelete := checkExpectedSubs(sl.NumSubscriptions())
		require_Equal(t, afterStreamCreate, afterConsumerDelete)

		require_NoError(t, js.DeleteStream("TEST"))
		afterStreamDelete := checkExpectedSubs(sl.NumSubscriptions())
		if baseline == 0 {
			baseline = afterStreamDelete
		}
		require_Equal(t, baseline, afterStreamDelete)
	}
}
TESTEOF

echo "Running TestDDBenchOracleLeakedSubsStreamImportOverlap ..."
go_oracle TestDDBenchOracleLeakedSubsStreamImportOverlap ./server/ -timeout 120s
go_verdict "Bug is fixed — subscription counts stay stable across create/delete cycles" \
           "Bug is present — subscriptions leak across stream/consumer create/delete cycles"
