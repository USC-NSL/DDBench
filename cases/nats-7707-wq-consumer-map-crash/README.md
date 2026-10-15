# NATS Server #7707: Concurrent Map Crash on WorkQueue Consumer Operations

| Field | Value |
|-------|-------|
| Project | [NATS Server](https://github.com/nats-io/nats-server) |
| Issue | [#7707](https://github.com/nats-io/nats-server/issues/7707) |
| Language | Go |
| Category | Concurrency crash (fatal map race) |

## Bug Summary

The NATS server crashes with a `fatal error: concurrent map iteration and map write` when multiple consumers are concurrently created and deleted on a WorkQueue retention stream with unique consumer partitioning. The crash is triggered when the partition uniqueness check iterates a map while another goroutine modifies it.

## Quick Start

```bash
# from the repository root
./bench.sh setup nats-7707-wq-consumer-map-crash        # build image + case repository, warm caches
./bench.sh reproduce nats-7707-wq-consumer-map-crash    # FAIL (exit 1) while the bug is present
./bench.sh shell nats-7707-wq-consumer-map-crash        # explore: source at /workspace/src, oracle at /bench/reproduce.sh
```

## Prerequisites

Docker (all toolchains are in the `bug-bench/nats` image; see the top-level README).

## Build Notes

- No special configuration: the oracle's Go test starts its own embedded single-node JetStream server with in-memory storage.

## What to Expect

**When the bug is present (FAIL):**
The Go race detector reports a `DATA RACE` or the test crashes with `fatal error: concurrent map iteration and map write` during concurrent consumer create/update/delete operations on a WorkQueue stream.

**When the bug is fixed (PASS):**
No race condition or crash is detected across 5 test iterations.

## Detailed Documentation

- [`symptom.md`](symptom.md) -- Observable behavior and error messages
- [`reproduce.md`](reproduce.md) -- Step-by-step reproduction procedure and what PASS/FAIL mean
- [`reproduce.sh`](reproduce.sh) -- The oracle (exit 0 PASS, 1 FAIL, 2 ERROR)
