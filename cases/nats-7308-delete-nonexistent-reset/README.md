# NATS Server #7308: Delete Non-Existent Message Triggers Cluster State Reset

| Field | Value |
|-------|-------|
| Project | [NATS Server](https://github.com/nats-io/nats-server) |
| Issue | [#7308](https://github.com/nats-io/nats-server/issues/7308) |
| Language | Go |
| Category | Cluster availability (stream becomes inaccessible) |

## Bug Summary

Deleting a message with a non-existent sequence number (beyond the stream's last sequence) on a clustered JetStream stream causes the entire cluster state to reset and triggers a leader election. The stream becomes inaccessible for several seconds. The root cause is in `applyStreamEntries`: when `removeMsg`/`eraseMsg` returns `ErrStoreEOF` for a sequence past the end of the stream, the code treats it as a fatal cluster error and returns it to the caller, which resets the stream's Raft state.

## Quick Start

```bash
# from the repository root
./bench.sh setup nats-7308-delete-nonexistent-reset        # build image + case repository, warm caches
./bench.sh reproduce nats-7308-delete-nonexistent-reset    # FAIL (exit 1) while the bug is present
./bench.sh shell nats-7308-delete-nonexistent-reset        # explore: source at /workspace/src, oracle at /bench/reproduce.sh
```

## Prerequisites

Docker (all toolchains are in the `bug-bench/nats` image; see the top-level README).

## What to Expect

**When the bug is present (FAIL):**
The test `TestJetStreamClusterDeleteMsgEOF` fails on the R3 subtest because deleting a non-existent sequence (past EOF) triggers a cluster state reset, causing the client call to timeout instead of returning an error.

**When the bug is fixed (PASS):**
The test passes -- deleting a non-existent sequence returns an appropriate error to the client without disrupting the cluster.

## Detailed Documentation

- [`symptom.md`](symptom.md) -- Observable behavior and error messages
- [`reproduce.md`](reproduce.md) -- Step-by-step reproduction procedure and what PASS/FAIL mean
- [`reproduce.sh`](reproduce.sh) -- The oracle (exit 0 PASS, 1 FAIL, 2 ERROR)
