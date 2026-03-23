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
The test `TestJetStreamWQMaxDeliveryReached` fails because messages that reached max-deliver are incorrectly removed from the WorkQueue stream.

**When the bug is fixed (PASS):**
The test passes -- messages that reached max-deliver are preserved in the stream.

## Detailed Documentation

- [`symptom.md`](symptom.md) -- Observable behavior and error messages
- [`setup.md`](setup.md) -- Detailed setup instructions
- [`reproduce.md`](reproduce.md) -- Step-by-step reproduction procedure
- [`verification.md`](verification.md) -- Pass/fail verification criteria
