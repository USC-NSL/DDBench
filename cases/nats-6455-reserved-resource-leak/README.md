# NATS Server #6455: Reserved Resources Leak After Cluster State Reset

| Field | Value |
|-------|-------|
| Project | [NATS Server](https://github.com/nats-io/nats-server) |
| Issue | [#6455](https://github.com/nats-io/nats-server/issues/6455) |
| Language | Go |
| Category | Resource accounting leak (reserved bytes double-counted) |

## Bug Summary

When a clustered JetStream stream hits a "last sequence mismatch" or "first sequence mismatch" error, `resetClusteredState()` tears down and recreates the stream. On recreation, `reserveStreamResources()` is called again without releasing the previous reservation, causing `MaxBytes` to be double-counted. Repeated resets cause reserved bytes to climb until the server reports disk full.

## Quick Start

```bash
# from the repository root
./bench.sh setup nats-6455-reserved-resource-leak        # build image + case repository, warm caches
./bench.sh reproduce nats-6455-reserved-resource-leak    # FAIL (exit 1) while the bug is present
./bench.sh shell nats-6455-reserved-resource-leak        # explore: source at /workspace/src, oracle at /bench/reproduce.sh
```

## Prerequisites

Docker (all toolchains are in the `bug-bench/nats` image; see the top-level README).

## What to Expect

**When the bug is present (FAIL):**
The test `TestJetStreamClusterReservedResourcesAccountingAfterClusterReset` fails because reserved store bytes are double-counted after a cluster state reset.

**When the bug is fixed (PASS):**
The test passes -- reserved bytes remain stable at the expected value.

## Detailed Documentation

- [`symptom.md`](symptom.md) -- Observable behavior and error messages
- [`reproduce.md`](reproduce.md) -- Step-by-step reproduction procedure and what PASS/FAIL mean
- [`reproduce.sh`](reproduce.sh) -- The oracle (exit 0 PASS, 1 FAIL, 2 ERROR)
