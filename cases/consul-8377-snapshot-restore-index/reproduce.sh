#!/usr/bin/env bash
# Reproduction and verification script for consul-8377-snapshot-restore-index
#
# Bug: During FSM snapshot restore, ensureNodeTxn/ensureServiceTxn/ensureCheckTxn
# unconditionally set CreateIndex = idx (the current Raft index) for new entries.
# Since the restore operates on an empty store, ALL entries are "new" and get
# their original CreateIndex overwritten with the restore Raft index.
#
# This test verifies the bug at the state store level by simulating a
# snapshot restore: it creates a fresh store, inserts catalog entries with a
# high restore index, and checks whether the original CreateIndex is preserved.
# ── Docker mode (preferred) ──
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
    exec "$REPO_ROOT/bench.sh" reproduce "$CASE_NAME"
fi
# ── Host fallback (no Docker) ──
set -uo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/consul-8377-snapshot-restore-index"

# ── Rebuild if source changed ──
[ -f "$WORK_DIR/REBUILD.sh" ] && bash "$WORK_DIR/REBUILD.sh"

# Verify setup
if [ ! -d "$WORK_DIR" ]; then
    echo "ERROR: Work directory not found. Run ./setup.sh first."
    exit 1
fi

echo "=== Reproducing consul-8377-snapshot-restore-index ==="

TEST_FILE="$WORK_DIR/agent/consul/state/snapshot_index_bug_test.go"

INJECTED=false
cleanup() {
    [ "$INJECTED" = true ] && rm -f "$TEST_FILE"
}
trap cleanup EXIT

TEST_NAME="TestSnapshotRestoreOverwritesCreateIndex"

# Skip injection if the fix commit already has this test
if grep -rq "func ${TEST_NAME}" "$WORK_DIR/agent/consul/state/"*_test.go 2>/dev/null; then
    echo "Test $TEST_NAME already exists in source (fix commit) — skipping injection"
else
    INJECTED=true
    # Inject a test that exercises the actual Snapshot() → Restore() cycle.
    # On the buggy code, Restore.Registration() calls ensureRegistrationTxn
    # which unconditionally sets CreateIndex = restore raft index.
    # On the fix code, Restore.Registration() passes preserveIndexes=true
    # and RegisterRequest carries RaftIndex from the snapshot data.
    #
    # The test uses reflection to conditionally set RaftIndex on RegisterRequest
    # (only present on the fix commit), so the same test compiles on both versions.
    cat > "$TEST_FILE" << 'GOEOF'
package state

import (
	"reflect"
	"testing"

	"github.com/hashicorp/consul/agent/structs"
)

func TestSnapshotRestoreOverwritesCreateIndex(t *testing.T) {
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
fi

echo "Running go test in agent/consul/state..."

cd "$WORK_DIR"
OUTPUT=$(go test -v -vet=off -run "^${TEST_NAME}$" -count=1 -timeout 120s ./agent/consul/state/ 2>&1)
TEST_EXIT=$?
echo "$OUTPUT" | tail -30

echo ""
if [ "$TEST_EXIT" -ne 0 ]; then
    echo "FAIL: Bug is present — CreateIndex overwritten with restore raft index during snapshot restore"
    exit 1
else
    echo "PASS: Bug is fixed — CreateIndex preserved during snapshot restore"
    exit 0
fi
