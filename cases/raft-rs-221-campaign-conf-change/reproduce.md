# Reproduction Procedure

## Quick start

```bash
cd cases/raft-rs-221-campaign-conf-change/
./setup.sh    # clone, checkout buggy commit, build test harness
./reproduce.sh  # inject test, run → PASS/FAIL
```

## What the reproduce script does

1. Appends `test_conf_change_check_before_campaign` to the integration test file.
2. Rebuilds the test harness if needed.
3. Runs the injected test via `cargo test`.

The test creates a 3-node Raft cluster, elects node 1 as leader, proposes a `RemoveNode(3)` conf change, and verifies:
- Node 2 does NOT campaign via election timeout while the conf change is committed but unapplied
- Node 2 does NOT campaign via `MsgTransferLeader` while the conf change is committed but unapplied
- After applying the conf change, node 2 CAN campaign and become leader
- After applying the conf change, node 1 CAN campaign normally

On the buggy commit, the `MsgTransferLeader` test assertion fails because `MsgTimeoutNow` bypasses the pending conf change check.

## Expected output (bug present)

```
test test_conf_change_check_before_campaign ... FAILED
assertion failed: `nt.peers[&2].state == StateRole::Follower`

FAIL: Bug is present — node campaigns despite pending conf change
```

## Expected output (bug fixed)

```
test test_conf_change_check_before_campaign ... ok

PASS: Bug is fixed — pending conf change blocks campaign
```
