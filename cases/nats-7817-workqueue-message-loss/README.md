# NATS Server #7817: WorkQueue Message Loss at Max Delivery

| Field | Value |
|-------|-------|
| Project | [NATS Server](https://github.com/nats-io/nats-server) |
| Issue | [#7817](https://github.com/nats-io/nats-server/issues/7817) |
| Language | Go |
| Category | Data loss (messages silently removed from WorkQueue) |

## Bug Summary

Messages are silently lost in a JetStream stream configured with WorkQueue retention policy and R3 replication when consumers reach their max-deliver limit. In `checkInterestState`, `noInterest(seq, o)` skips the calling consumer, so messages that reached max deliveries are incorrectly considered as having no interest and removed from the stream.

## Quick Start

```bash
# from the repository root
./bench.sh setup nats-7817-workqueue-message-loss        # build image + case repository, warm caches
./bench.sh reproduce nats-7817-workqueue-message-loss    # FAIL (exit 1) while the bug is present
./bench.sh shell nats-7817-workqueue-message-loss        # explore: source at /workspace/src, oracle at /bench/reproduce.sh
```

## Prerequisites

Docker (all toolchains are in the `bug-bench/nats` image; see the top-level README).

## Build Notes

- The `nats` CLI used by the manual procedure is preinstalled (pinned) in the image.

## What to Expect

**When the bug is present (FAIL):**
The test `TestJetStreamWQMaxDeliveryReached` fails because messages that reached max-deliver are incorrectly removed from the WorkQueue stream.

**When the bug is fixed (PASS):**
The test passes -- messages that reached max-deliver are preserved in the stream.

## Detailed Documentation

- [`symptom.md`](symptom.md) -- Observable behavior and error messages
- [`reproduce.md`](reproduce.md) -- Step-by-step reproduction procedure and what PASS/FAIL mean
- [`reproduce.sh`](reproduce.sh) -- The oracle (exit 0 PASS, 1 FAIL, 2 ERROR)
