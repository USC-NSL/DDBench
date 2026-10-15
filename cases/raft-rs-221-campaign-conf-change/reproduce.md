# Reproduction Procedure

## Quick start

```bash
# from the repository root
./bench.sh setup raft-rs-221-campaign-conf-change      # case repository at the buggy commit, build test harness
./bench.sh reproduce raft-rs-221-campaign-conf-change  # inject test, run → PASS/FAIL
```

Inside `./bench.sh shell raft-rs-221-campaign-conf-change` (source at `/workspace/src`), the same oracle runs as `bash /bench/reproduce.sh`.

## What the reproduce script does

1. Appends `test_ddbench_oracle_campaign_pending_conf_change` to the integration test file.
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
test test_ddbench_oracle_campaign_pending_conf_change ... FAILED
assertion failed: `nt.peers[&2].state == StateRole::Follower`

FAIL: Bug is present — the node campaigns despite a pending conf change
```

## Expected output (bug fixed)

```
test test_ddbench_oracle_campaign_pending_conf_change ... ok

PASS: Bug is fixed — a pending conf change blocks the campaign
```

## Oracle verdict

`./bench.sh reproduce raft-rs-221-campaign-conf-change` rebuilds the worktree and runs the oracle (`reproduce.sh`), which decides from cargo's status line for `test_ddbench_oracle_campaign_pending_conf_change`:

- **FAIL** (exit 1): the injected test fails, e.g. node 2 campaigns (via election timeout or `MsgTransferLeader`) while the `RemoveNode(3)` conf change is committed but not applied, or the test is ignored. A worktree that does not build, or an injected test that does not compile, is also FAIL.
- **PASS** (exit 0): the injected test passes: no campaign while the conf change is pending, and nodes 1 and 2 can campaign once it is applied.
- **ERROR** (exit 2): the case is not set up (`REBUILD.sh` or `tests/integration_cases/test_raft.rs` is missing), or the test did not run and no compilation error explains it.
