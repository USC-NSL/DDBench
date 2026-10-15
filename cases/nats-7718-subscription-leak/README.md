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
# from the repository root
./bench.sh setup nats-7718-subscription-leak        # build image + case repository, warm caches
./bench.sh reproduce nats-7718-subscription-leak    # FAIL (exit 1) while the bug is present
./bench.sh shell nats-7718-subscription-leak        # explore: source at /workspace/src, oracle at /bench/reproduce.sh
```

## Prerequisites

Docker (all toolchains are in the `bug-bench/nats` image; see the top-level README).

## What to Expect

**When the bug is present (FAIL):**
The test `TestJetStreamClusterLeakedSubsWithStreamImportOverlappingJetStreamSubs` fails because subscription counts diverge after stream/consumer create/delete cycles with overlapping account imports.

**When the bug is fixed (PASS):**
The test passes -- all subscriptions are properly cleaned up.

## Detailed Documentation

- [`symptom.md`](symptom.md) -- Observable behavior and error messages
- [`reproduce.md`](reproduce.md) -- Step-by-step reproduction procedure and what PASS/FAIL mean
- [`reproduce.sh`](reproduce.sh) -- The oracle (exit 0 PASS, 1 FAIL, 2 ERROR)
