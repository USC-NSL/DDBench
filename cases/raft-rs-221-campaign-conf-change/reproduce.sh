#!/usr/bin/env bash
# Reproduction and verification script for raft-rs-221-campaign-conf-change
# Appends a test to tests/integration_cases/test_raft.rs: a follower with a
# committed but unapplied conf change must not campaign (election timeout or
# MsgTimeoutNow) until the change is applied.
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

# ── cargo test verdicts ──
# Decided from libtest's per-test status line for the exact oracle test
# ("test <path>::<name> ... ok"); output capture stays on (no --nocapture), so
# code under test cannot print that line itself.
cargo_verdict() {  # <log> <test-name> <cargo-exit> <pass-message> <fail-message>
    if grep -qE "^test (.*::)?$2 \.\.\. ok$" "$1" && [ "$3" -eq 0 ]; then pass "$4"; fi
    if grep -qE "^test (.*::)?$2 \.\.\. FAILED$" "$1"; then fail "$5"; fi
    if grep -qE "^test (.*::)?$2 \.\.\. ignored" "$1"; then fail "the oracle test was ignored"; fi
    if grep -qE '^error(\[E[0-9]+\])?:|could not compile' "$1"; then
        fail "the oracle test did not run: the worktree or the injected oracle test does not compile"
    fi
    error "the oracle test did not run (cargo exit $3)"
}

TEST_FILE="$WORK_DIR/tests/integration_cases/test_raft.rs"
ORACLE=test_ddbench_oracle_campaign_pending_conf_change
LOG="$RUN_DIR/cargo-test.log"
export PATH="$HOME/.cargo/bin:$PATH"

rebuild_worktree
[ -f "$TEST_FILE" ] || error "tests/integration_cases/test_raft.rs not found in $WORK_DIR (run setup first)"

echo "=== Reproducing raft-rs-221-campaign-conf-change ==="

# Always appended fresh under a ddbench-only name; the worktree's version of
# the test file is restored afterwards.
cp "$TEST_FILE" "$RUN_DIR/test_raft.rs.saved"
cleanup() {
    cp "$RUN_DIR/test_raft.rs.saved" "$TEST_FILE"
    # The integration-test binary compiled with the oracle test must not outlive the run.
    local t
    for t in "$WORK_DIR/target"; do
        rm -rf "$t"/debug/deps/tests-* "$t"/debug/incremental/tests-* 2>/dev/null
    done
}
trap cleanup EXIT
cat >> "$TEST_FILE" << 'RUSTEOF'
/// Tests if unapplied conf change is checked before campaign.
///
/// Setup: 3-node cluster. Leader (node 1) proposes RemoveNode(3). The conf change
/// is committed but not yet applied on node 2. When node 2 receives MsgTimeoutNow
/// (leader transfer) or its election timer fires, it should NOT campaign because
/// the pending conf change means the voter set is stale. On the buggy commit,
/// MsgTimeoutNow bypasses the pending conf change check and campaigns immediately
/// with wrong quorum, potentially causing election failure or split-brain.
#[test]
fn test_ddbench_oracle_campaign_pending_conf_change() {
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

cd "$WORK_DIR/."
echo "Running $ORACLE ..."
RUSTFLAGS='--cap-lints allow' cargo test "$ORACLE" > "$LOG" 2>&1
rc=$?
grep -E "^test |test result|^error|panicked" "$LOG" | tail -20
cargo_verdict "$LOG" "$ORACLE" "$rc" \
    "Bug is fixed — a pending conf change blocks the campaign" \
    "Bug is present — the node campaigns despite a pending conf change"
