# NATS Server #7718: Leaked Subscriptions with Overlapping Stream Imports

| Field | Value |
|-------|-------|
| Project | [NATS Server](https://github.com/nats-io/nats-server) |
| Issue | [#7718](https://github.com/nats-io/nats-server/issues/7718) |
| Language | Go |
| Category | Resource leak (subscription leak) |

## Bug Summary

When using JetStream with overlapping stream imports (e.g., importing both `events.>` and `events.critical.>` from the same account), rapidly creating and destroying OrderedConsumers causes a subscription leak. The subscription cleanup logic fails to remove subscriptions from all overlapping import paths, leaving orphaned subscriptions that grow continuously.

## Quick Start

```bash
# 1. Set up the codebase (clone, checkout buggy commit)
./setup.sh

# 2. Reproduce the bug and verify
./reproduce.sh
```

## Prerequisites

- Git
- Go 1.22+ (expected at /usr/local/go/bin/go)

## What to Expect

**When the bug is present (FAIL):**
The test `TestJetStreamClusterLeakedSubsWithStreamImportOverlappingJetStreamSubs` fails because subscription counts diverge after stream/consumer create/delete cycles with overlapping account imports.

**When the bug is fixed (PASS):**
The test passes -- all subscriptions are properly cleaned up.

## Detailed Documentation

- [`symptom.md`](symptom.md) -- Observable behavior and error messages
- [`setup.md`](setup.md) -- Detailed setup instructions
- [`reproduce.md`](reproduce.md) -- Step-by-step reproduction procedure
- [`verification.md`](verification.md) -- Pass/fail verification criteria
