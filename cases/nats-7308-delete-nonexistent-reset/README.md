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
# 1. Set up the codebase (clone, checkout buggy version)
./setup.sh

# 2. Reproduce the bug and verify
./reproduce.sh
```

## Prerequisites

- Git
- Go 1.22+ (expected at /usr/local/go/bin/go)

## What to Expect

**When the bug is present (FAIL):**
The test `TestJetStreamClusterDeleteMsgEOF` fails on the R3 subtest because deleting a non-existent sequence (past EOF) triggers a cluster state reset, causing the client call to timeout instead of returning an error.

**When the bug is fixed (PASS):**
The test passes -- deleting a non-existent sequence returns an appropriate error to the client without disrupting the cluster.

## Detailed Documentation

- [`symptom.md`](symptom.md) -- Observable behavior and error messages
- [`reproduce.md`](reproduce.md) -- Step-by-step reproduction procedure
- [`verification.md`](verification.md) -- Pass/fail verification criteria
