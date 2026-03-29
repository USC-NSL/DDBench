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
# 1. Set up the codebase (clone, checkout buggy commit, build)
./setup.sh

# 2. Reproduce the bug and verify
./reproduce.sh
```

## Prerequisites

- Git, Go (1.13+)

## What to Expect

**When the bug is present (FAIL):**
A fresh subscriber (Index=0) receives a `newSnapshotToFollow` framing event from the cached snapshot, which should only appear for stale-index resume requests. The test detects this incorrect behavior.

**When the bug is fixed (PASS):**
The cached snapshot contains only data events, and the `newSnapshotToFollow` framing event is prepended only for individual stale-index requests, not stored in the cache.

## Detailed Documentation

- [`symptom.md`](symptom.md) -- Observable behavior and error messages
- [`setup.md`](setup.md) -- Detailed setup instructions
- [`reproduce.md`](reproduce.md) -- Step-by-step reproduction procedure
- [`verification.md`](verification.md) -- Pass/fail verification criteria
