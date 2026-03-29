# Kvrocks #3208: Replication Stall After Large Batch Due to Stuck Read Watermark

| Field | Value |
|-------|-------|
| Project | [Kvrocks](https://github.com/apache/kvrocks) |
| Issue | [#3208](https://github.com/apache/kvrocks/issues/3208) |
| Language | C++ |
| Category | Logic error (replication stall) |

## Bug Summary

After a large replication batch (e.g., 16 KB) is received by the replica, the I/O read threshold is set high but never reset. Subsequent smaller data from the master is not processed by the replica until enough bytes accumulate to meet the stale threshold, causing replication to stall for minutes to hours with no errors in the logs.

## Quick Start

```bash
# 1. Set up the codebase (clone, checkout buggy commit, build)
./setup.sh

# 2. Reproduce the bug and verify
./reproduce.sh
```

## Prerequisites

- Git, C++ compiler, CMake
- redis-cli (for interacting with Kvrocks)
- Python 3 (for generating large values)

## What to Expect

**When the bug is present (FAIL):**
A small value written to master after a large batch does not appear on the replica within 5 seconds. The replication stream is stalled.

**When the bug is fixed (PASS):**
The small value appears on the replica within seconds, regardless of the prior batch size.

## Detailed Documentation

- [`symptom.md`](symptom.md) -- Observable behavior and error messages
- [`setup.md`](setup.md) -- Detailed setup instructions
- [`reproduce.md`](reproduce.md) -- Step-by-step reproduction procedure
- [`verification.md`](verification.md) -- Pass/fail verification criteria
