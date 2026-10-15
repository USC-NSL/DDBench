# RabbitMQ #12635: Quorum Queue Crash After Raft Snapshot Installation

| Field | Value |
|-------|-------|
| Project | [RabbitMQ](https://github.com/rabbitmq/rabbitmq-server) |
| Issue | [#12635](https://github.com/rabbitmq/rabbitmq-server/issues/12635) |
| Language | Erlang/OTP |
| Category | Raft state machine crash (stale log read after snapshot installation) |

## Bug Summary

A quorum queue member crashes after installing a Raft snapshot when it tries to deliver messages to local consumers. The crash occurs in `rabbit_fifo:delivery_effect/3` because the function uses `lists:zipwith` to pair log entries with message metadata, but after a snapshot installation the log may return fewer entries than requested (the entries were already consumed and checkpointed on the leader). The mismatched list lengths cause `lists:zipwith` to crash.

The bug is triggered when a slow or stopped follower has consumers on its node. After the follower installs a snapshot that references these consumers, it tries to read log entries for messages that no longer exist in its log, causing the crash.

## Quick Start

```bash
# from the repository root
./bench.sh setup rabbitmq-12635-qq-snapshot-crash        # build image + case repository, warm caches
./bench.sh reproduce rabbitmq-12635-qq-snapshot-crash    # FAIL (exit 1) while the bug is present
./bench.sh shell rabbitmq-12635-qq-snapshot-crash        # explore: source at /workspace/src, oracle at /bench/reproduce.sh
```

## Prerequisites

Docker (all toolchains are in the `bug-bench/rabbitmq` image; see the top-level README).

## What to Expect

**When the bug is present (FAIL):**
The CT test fails. The quorum queue member on the third node crashes with a `lists:zipwith` error after installing the Raft snapshot. The test detects the crash via a process monitor `DOWN` message.

**When the bug is fixed (PASS):**
The CT test passes. The `delivery_effect/3` function gracefully handles the stale log read by checking the number of returned commands and returning empty effects when they don't match.

## Detailed Documentation

- [`symptom.md`](symptom.md) -- Observable behavior and error messages
- [`reproduce.md`](reproduce.md) -- Step-by-step reproduction procedure and what PASS/FAIL mean
- [`reproduce.sh`](reproduce.sh) -- The oracle (exit 0 PASS, 1 FAIL, 2 ERROR)
