# NATS Server #6374: Stuck Consumer When Deleting Non-Acked Messages

| Field | Value |
|-------|-------|
| Project | [NATS Server](https://github.com/nats-io/nats-server) |
| Issue | [#6374](https://github.com/nats-io/nats-server/issues/6374) |
| Language | Go |
| Category | Consumer state corruption (stuck consumer after leader step-down + redelivery race) |

## Bug Summary

Two related bugs cause a JetStream consumer to become stuck or severely slow:

1. When a consumer leader steps down while inflight acks exist, `o.ackMsgs.drain()` clears the ack queue but `o.awl` is not reset to zero. The stale `o.awl` causes `checkPending` to short-circuit, preventing all message redelivery.

2. When a message scheduled for redelivery has been deleted from the stream, `getNextMsg()` returns the error without cleaning the stale entry from `o.pending` and `o.rdc`, causing repeated failed load attempts and consumer slowdown.

## Quick Start

```bash
# from the repository root
./bench.sh setup nats-6374-consumer-stuck-redelivery        # build image + case repository, warm caches
./bench.sh reproduce nats-6374-consumer-stuck-redelivery    # FAIL (exit 1) while the bug is present
./bench.sh shell nats-6374-consumer-stuck-redelivery        # explore: source at /workspace/src, oracle at /bench/reproduce.sh
```

## Prerequisites

Docker (all toolchains are in the `bug-bench/nats` image; see the top-level README).

## What to Expect

**When the bug is present (FAIL):**
Both tests fail. The first test times out waiting for a redelivered message after a simulated leader step-down. The second test gets the wrong error and finds stale entries in pending/rdc maps.

**When the bug is fixed (PASS):**
Both tests pass. The consumer correctly redelivers messages after leader step-down, and deleted messages are properly cleaned from redelivery tracking.

## Detailed Documentation

- [`symptom.md`](symptom.md) -- Observable behavior and error messages
- [`reproduce.md`](reproduce.md) -- Step-by-step reproduction procedure and what PASS/FAIL mean
- [`reproduce.sh`](reproduce.sh) -- The oracle (exit 0 PASS, 1 FAIL, 2 ERROR)
