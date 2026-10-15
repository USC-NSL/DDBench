#!/usr/bin/env bash
# Reproduction and verification script for raft-rs-345-readindex-config-change
# Appends a test to harness/tests/integration_cases/test_raft.rs: a pending
# ReadIndex request must complete when a conf change removes the peer whose
# acknowledgement was missing (quorum shrinks to the leader alone).
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

TEST_FILE="$WORK_DIR/harness/tests/integration_cases/test_raft.rs"
ORACLE=test_ddbench_oracle_read_index_quorum_shrinks
LOG="$RUN_DIR/cargo-test.log"
export PATH="$HOME/.cargo/bin:$PATH"

rebuild_worktree
[ -f "$TEST_FILE" ] || error "harness/tests/integration_cases/test_raft.rs not found in $WORK_DIR (run setup first)"

echo "=== Reproducing raft-rs-345-readindex-config-change ==="

# Always appended fresh under a ddbench-only name; the worktree's version of
# the test file is restored afterwards.
cp "$TEST_FILE" "$RUN_DIR/test_raft.rs.saved"
cleanup() {
    cp "$RUN_DIR/test_raft.rs.saved" "$TEST_FILE"
    # The integration-test binary compiled with the oracle test must not outlive the run.
    local t
    for t in "$WORK_DIR/target" "$WORK_DIR/harness/target"; do
        rm -rf "$t"/debug/deps/tests-* "$t"/debug/incremental/tests-* 2>/dev/null
    done
}
trap cleanup EXIT
cat >> "$TEST_FILE" << 'RUSTEOF'
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
fn test_ddbench_oracle_read_index_quorum_shrinks() {
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

cd "$WORK_DIR/harness"
echo "Running $ORACLE ..."
cargo test "$ORACLE" > "$LOG" 2>&1
rc=$?
grep -E "^test |test result|^error|panicked" "$LOG" | tail -20
cargo_verdict "$LOG" "$ORACLE" "$rc" \
    "Bug is fixed — ReadIndex completes after the quorum shrinks" \
    "Bug is present — ReadIndex stalls after the quorum shrinks"
