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
The Go race detector reports a `DATA RACE` or the test crashes with `fatal error: concurrent map iteration and map write` during concurrent consumer create/update/delete operations on a WorkQueue stream.

**When the bug is fixed (PASS):**
No race condition or crash is detected across 5 test iterations.

## Detailed Documentation

- [`symptom.md`](symptom.md) -- Observable behavior and error messages
- [`setup.md`](setup.md) -- Detailed setup instructions
- [`reproduce.md`](reproduce.md) -- Step-by-step reproduction procedure
- [`verification.md`](verification.md) -- Pass/fail verification criteria
