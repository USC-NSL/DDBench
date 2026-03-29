#!/usr/bin/env bash
# Reproduction and verification script for raft-rs-221-campaign-conf-change
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
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/raft-rs-221-campaign-conf-change"
export PATH="$HOME/.cargo/bin:$PATH"

# ── Rebuild if source changed ──
[ -f "$WORK_DIR/REBUILD.sh" ] && bash "$WORK_DIR/REBUILD.sh"

# Verify setup
if [ ! -d "$WORK_DIR/tests" ]; then
    echo "ERROR: Workspace not found at $WORK_DIR. Run ./setup.sh first."
    exit 1
fi

echo "=== Reproducing raft-rs-221-campaign-conf-change ==="

cd "$WORK_DIR"

TEST_FILE="tests/integration_cases/test_raft.rs"

# Check if test already injected
if grep -q "test_conf_change_check_before_campaign" "$TEST_FILE" 2>/dev/null; then
    echo "Test already injected."
else
    echo "Injecting regression test..."
    cat >> "$TEST_FILE" <<'RUSTEOF'

/// Tests if unapplied conf change is checked before campaign.
/// Regression test for https://github.com/tikv/raft-rs/issues/221
///
/// Setup: 3-node cluster. Leader (node 1) proposes RemoveNode(3). The conf change
/// is committed but not yet applied on node 2. When node 2 receives MsgTimeoutNow
/// (leader transfer) or its election timer fires, it should NOT campaign because
/// the pending conf change means the voter set is stale. On the buggy commit,
/// MsgTimeoutNow bypasses the pending conf change check and campaigns immediately
/// with wrong quorum, potentially causing election failure or split-brain.
#[test]
fn test_conf_change_check_before_campaign() {
    setup_for_test();
    let mut nt = Network::new(vec![None, None, None]);
    nt.send(vec![new_message(1, 1, MessageType::MsgHup, 0)]);
    assert_eq!(nt.peers[&1].state, StateRole::Leader);

    let mut m = new_message(1, 1, MessageType::MsgPropose, 0);
    let mut e = Entry::new();
    e.set_entry_type(EntryType::EntryConfChange);
    let mut cc = ConfChange::new();
    cc.set_change_type(ConfChangeType::RemoveNode);
    cc.set_node_id(3);
    e.set_data(protobuf::Message::write_to_bytes(&cc).unwrap());
    m.mut_entries().push(e);
    nt.send(vec![m]);

    // trigger campaign in node 2
    nt.peers
        .get_mut(&2)
        .unwrap()
        .reset_randomized_election_timeout();
    let timeout = nt.peers[&2].get_randomized_election_timeout();
    for _ in 0..timeout {
        nt.peers.get_mut(&2).unwrap().tick();
    }
    // It's still follower because committed conf change is not applied.
    assert_eq!(nt.peers[&2].state, StateRole::Follower);

    // Transfer leadership to peer 2.
    nt.send(vec![new_message(2, 1, MessageType::MsgTransferLeader, 0)]);
    assert_eq!(nt.peers[&1].state, StateRole::Leader);
    // It's still follower because committed conf change is not applied.
    assert_eq!(nt.peers[&2].state, StateRole::Follower);
    // Abort transfer leader.
    nt.peers.get_mut(&1).unwrap().abort_leader_transfer();

    let committed = nt.peers[&2].raft_log.committed;
    nt.peers.get_mut(&2).unwrap().raft_log.applied_to(committed);
    nt.peers.get_mut(&2).unwrap().remove_node(3);

    // transfer leadership to peer 2 again.
    nt.send(vec![new_message(2, 1, MessageType::MsgTransferLeader, 0)]);
    assert_eq!(nt.peers[&1].state, StateRole::Follower);
    assert_eq!(nt.peers[&2].state, StateRole::Leader);

    nt.peers.get_mut(&1).unwrap().raft_log.applied_to(committed);
    nt.peers.get_mut(&1).unwrap().remove_node(3);

    // trigger campaign in node 1
    nt.peers
        .get_mut(&1)
        .unwrap()
        .reset_randomized_election_timeout();
    let timeout = nt.peers[&1].get_randomized_election_timeout();
    for _ in 0..timeout {
        nt.peers.get_mut(&1).unwrap().tick();
    }
    assert_eq!(nt.peers[&1].state, StateRole::Candidate);
}
RUSTEOF
fi

# Run the specific test
echo "Running regression test..."
set +e
RESULT=$(RUSTFLAGS='--cap-lints allow' cargo test test_conf_change_check_before_campaign -- --nocapture 2>&1)
EXIT_CODE=$?
set -e

echo "$RESULT" | tail -20

echo ""
if [ $EXIT_CODE -eq 0 ]; then
    echo "PASS: Bug is fixed — pending conf change blocks campaign"
    exit 0
else
    echo "FAIL: Bug is present — node campaigns despite pending conf change"
    exit 1
fi
