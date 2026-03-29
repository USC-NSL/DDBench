#!/usr/bin/env bash
# Reproduction and verification script for raft-rs-345-readindex-config-change
# Injects a Rust test into the harness, runs it, and reports PASS/FAIL.
# ── Docker mode (preferred) ──
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
    exec "$REPO_ROOT/bench.sh" reproduce "$CASE_NAME"
fi
# ── Host fallback (no Docker) ──
set -uo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/raft-rs-345-readindex-config-change"
export PATH="$HOME/.cargo/bin:$PATH"

# ── Rebuild if source changed ──
[ -f "$WORK_DIR/REBUILD.sh" ] && bash "$WORK_DIR/REBUILD.sh"

# Verify setup
if [ ! -d "$WORK_DIR/harness" ]; then
    echo "ERROR: Workspace not found at $WORK_DIR. Run ./setup.sh first."
    exit 1
fi

echo "=== Reproducing raft-rs-345-readindex-config-change ==="

cd "$WORK_DIR"

TEST_FILE="harness/tests/integration_cases/test_raft.rs"

# Check if test already injected
if grep -q "test_read_when_quorum_becomes_less_bug" "$TEST_FILE" 2>/dev/null; then
    echo "Test already injected."
else
    echo "Injecting regression test..."
    cat >> "$TEST_FILE" <<'RUSTEOF'

// Regression test for https://github.com/tikv/raft-rs/issues/345
// ReadIndex stall after quorum shrinks on config change.
//
// Setup: 2-node cluster (nodes 1,2). Leader (node 1) receives a ReadIndex
// request. Heartbeats are broadcast but the response from node 2 is dropped,
// so the read cannot complete (quorum=2 requires both acks). Then node 2 is
// removed via config change, shrinking quorum to 1. The leader already has its
// own ack, which is now sufficient. With the bug, read_states stays empty
// because pending reads are not re-evaluated; with the fix, read_states is
// populated immediately.
#[test]
fn test_read_when_quorum_becomes_less_bug() {
    let l = default_logger();
    let mut network = Network::new(vec![None, None], &l);

    // Elect node 1 as leader.
    let mut m = Message::default();
    m.from = 1;
    m.to = 1;
    m.set_msg_type(MessageType::MsgHup);
    network.send(vec![m]);
    assert_eq!(network.peers[&1].raft_log.committed, 1);

    // Send a ReadIndex request to the leader.
    let mut m = Message::default();
    m.to = 1;
    m.set_msg_type(MessageType::MsgReadIndex);
    let mut e = Entry::default();
    e.data = b"abcdefg".to_vec();
    m.set_entries(vec![e].into());
    network.dispatch(vec![m]).unwrap();

    // Broadcast heartbeats from the leader.
    let heartbeats = network.read_messages();
    network.dispatch(heartbeats).unwrap();

    // Drop heartbeat response from peer 2 — only 1 ack (self), not enough for quorum=2.
    let heartbeat_responses = network.read_messages();
    assert_eq!(heartbeat_responses.len(), 1);

    // Now remove node 2, shrinking quorum from 2 to 1.
    // The leader's self-ack should now be sufficient to complete the read.
    network.peers.get_mut(&1).unwrap().remove_node(2).unwrap();

    // BUG: On the buggy commit, read_states is empty because pending reads
    // are not re-evaluated when quorum shrinks.
    // FIX: read_states should be non-empty — the read completes immediately.
    assert!(
        !network.peers[&1].read_states.is_empty(),
        "BUG: ReadIndex request stuck after quorum shrank — read_states is empty"
    );
}
RUSTEOF
fi

# Run the specific test
echo "Running regression test..."
cd harness
RESULT=$(cargo test test_read_when_quorum_becomes_less_bug -- --nocapture 2>&1)
EXIT_CODE=$?

echo "$RESULT" | tail -20

echo ""
if [ $EXIT_CODE -eq 0 ]; then
    echo "PASS: Bug is fixed — ReadIndex completes after quorum shrinks"
    exit 0
else
    echo "FAIL: Bug is present — ReadIndex stalls after quorum shrinks"
    exit 1
fi
