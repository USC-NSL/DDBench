#!/usr/bin/env bash
# Reproduction and verification script for consul-8377-snapshot-restore-index
# Injects a test into agent/consul/state that runs a real Snapshot() -> Restore()
# cycle and checks that a node's CreateIndex survives the restore.
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

ORACLE="TestDDBenchOracleSnapshotRestoreCreateIndex"
ORACLE_FILE="$WORK_DIR/agent/consul/state/zz_ddbench_oracle_test.go"


rebuild_worktree
[ -d "$WORK_DIR/agent/consul/state" ] || error "package agent/consul/state not found in $WORK_DIR (run setup first)"

echo "=== Reproducing consul-8377-snapshot-restore-index ==="

cleanup() { rm -f "$ORACLE_FILE"; }
trap cleanup EXIT

# Always inject fresh, under a ddbench-only name and file (never skipped).
# RaftIndex is set on the restore request via reflection only when that field
# exists, so the same test compiles on the buggy and on the fixed tree.
cat > "$ORACLE_FILE" << 'GOEOF'
package state

import (
	"reflect"
	"testing"

	"github.com/hashicorp/consul/agent/structs"
)

func TestDDBenchOracleSnapshotRestoreCreateIndex(t *testing.T) {
	// Step 1: Create a store with entries at known raft indexes.
	s1 := testStateStore(t)

	origIdx := uint64(10)
	req := &structs.RegisterRequest{
		Node:    "nodeA",
		Address: "10.0.0.1",
	}
	if err := s1.EnsureRegistration(origIdx, req); err != nil {
		t.Fatalf("register: %v", err)
	}

	// Verify the original CreateIndex
	_, origNode, err := s1.GetNode("nodeA")
	if err != nil || origNode == nil {
		t.Fatalf("get original node: %v", err)
	}
	t.Logf("Original nodeA.CreateIndex = %d (expected %d)", origNode.CreateIndex, origIdx)
	if origNode.CreateIndex != origIdx {
		t.Fatalf("unexpected original CreateIndex: got %d, want %d", origNode.CreateIndex, origIdx)
	}

	// Step 2: Snapshot the store.
	snap := s1.Snapshot()
	defer snap.Close()
	nodes, err := snap.Nodes()
	if err != nil {
		t.Fatalf("snapshot nodes: %v", err)
	}

	// Step 3: Restore into a new (empty) store.
	s2 := testStateStore(t)
	restore := s2.Restore()

	restoreIdx := uint64(100) // Simulates the Raft index at restore time

	for raw := nodes.Next(); raw != nil; raw = nodes.Next() {
		n := raw.(*structs.Node)

		restoreReq := structs.RegisterRequest{
			ID:              n.ID,
			Node:            n.Node,
			Address:         n.Address,
			Datacenter:      n.Datacenter,
			TaggedAddresses: n.TaggedAddresses,
			NodeMeta:        n.Meta,
		}

		// On the fix commit, RegisterRequest has an embedded RaftIndex field.
		// Set it from the snapshot Node so Restore.Registration() can preserve it.
		// On the buggy commit, the field does not exist — reflection is a no-op.
		reqVal := reflect.ValueOf(&restoreReq).Elem()
		if raftField := reqVal.FieldByName("RaftIndex"); raftField.IsValid() {
			nodeVal := reflect.ValueOf(n).Elem()
			if nodeRaft := nodeVal.FieldByName("RaftIndex"); nodeRaft.IsValid() {
				raftField.Set(nodeRaft)
				t.Logf("Set RaftIndex on RegisterRequest: CreateIndex=%d ModifyIndex=%d",
					nodeRaft.FieldByName("CreateIndex").Uint(),
					nodeRaft.FieldByName("ModifyIndex").Uint())
			}
		}

		if err := restore.Registration(restoreIdx, &restoreReq); err != nil {
			t.Fatalf("restore registration: %v", err)
		}
	}

	if err := restore.Commit(); err != nil {
		t.Fatalf("restore commit: %v", err)
	}

	// Step 4: Read back from the restored store and check CreateIndex.
	_, restoredNode, err := s2.GetNode("nodeA")
	if err != nil || restoredNode == nil {
		t.Fatalf("get restored node: %v", err)
	}

	t.Logf("Restored nodeA.CreateIndex = %d (original=%d, restoreIdx=%d)",
		restoredNode.CreateIndex, origIdx, restoreIdx)

	// On the buggy code:
	//   Restore.Registration(100, req) → ensureRegistrationTxn(tx, 100, req)
	//   → node.CreateIndex = 100 (overwritten with restore idx)
	//
	// On the fixed code:
	//   Restore.Registration(100, req) → ensureRegistrationTxn(tx, 100, true, req)
	//   → node.CreateIndex = req.CreateIndex = 10 (preserved from snapshot)
	if restoredNode.CreateIndex == restoreIdx {
		t.Fatalf("FAIL: Bug is present — CreateIndex (%d) overwritten with restore raft index (%d). "+
			"Expected original CreateIndex (%d) to be preserved during snapshot restore.",
			restoredNode.CreateIndex, restoreIdx, origIdx)
	}

	if restoredNode.CreateIndex == origIdx {
		t.Log("OK: CreateIndex correctly preserved during snapshot restore")
	} else {
		t.Fatalf("FAIL: CreateIndex is %d (expected original %d or restore %d)",
			restoredNode.CreateIndex, origIdx, restoreIdx)
	}
}
GOEOF

cd "$WORK_DIR"
echo "Running $ORACLE ..."
go_oracle "$ORACLE" ./agent/consul/state/ -vet=off -timeout 120s
go_verdict "Bug is fixed — CreateIndex preserved during snapshot restore" \
           "Bug is present — CreateIndex overwritten with the restore raft index"
