# Consul #9772: Streaming Snapshot Cache Bug

| Field | Value |
|-------|-------|
| Project | [Consul](https://github.com/hashicorp/consul) |
| PR | [#9772](https://github.com/hashicorp/consul/pull/9772) |
| Language | Go |
| Category | Logic error (incorrect snapshot caching in event publisher) |

## Bug Summary

When a streaming subscriber resumes with a stale index (`Index > 0`) and the topic buffer has moved past the requested index, the EventPublisher builds a new snapshot prepended with a `newSnapshotToFollow` framing event. This combined snapshot (framing event + data) is then cached. When a subsequent fresh subscriber (`Index=0`) receives this cached snapshot, it encounters the unexpected `newSnapshotToFollow` framing event at the start, causing the client to error.

## Quick Start

```bash
# from the repository root
./bench.sh setup consul-9772-streaming-snapshot-cache        # build image + case repository, warm caches
./bench.sh reproduce consul-9772-streaming-snapshot-cache    # FAIL (exit 1) while the bug is present
./bench.sh shell consul-9772-streaming-snapshot-cache        # explore: source at /workspace/src, oracle at /bench/reproduce.sh
```

## Prerequisites

Docker (all toolchains are in the `bug-bench/consul` image; see the top-level README).

## Build Notes

- A full `consul` binary is not required (its build is best-effort); the bug is reproduced by a Go unit test in `agent/consul/stream/`.

## What to Expect

**When the bug is present (FAIL):**
A fresh subscriber (Index=0) receives a `newSnapshotToFollow` framing event from the cached snapshot, which should only appear for stale-index resume requests. The test detects this incorrect behavior.

**When the bug is fixed (PASS):**
The cached snapshot contains only data events, and the `newSnapshotToFollow` framing event is prepended only for individual stale-index requests, not stored in the cache.

## Detailed Documentation

- [`symptom.md`](symptom.md) -- Observable behavior and error messages
- [`reproduce.md`](reproduce.md) -- Step-by-step reproduction procedure and what PASS/FAIL mean
- [`reproduce.sh`](reproduce.sh) -- The oracle (exit 0 PASS, 1 FAIL, 2 ERROR)
