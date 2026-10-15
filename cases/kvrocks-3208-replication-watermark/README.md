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
# from the repository root
./bench.sh setup kvrocks-3208-replication-watermark        # build image + case repository, warm caches
./bench.sh reproduce kvrocks-3208-replication-watermark    # FAIL (exit 1) while the bug is present
./bench.sh shell kvrocks-3208-replication-watermark        # explore: source at /workspace/src, oracle at /bench/reproduce.sh
```

## Prerequisites

Docker (all toolchains are in the `bug-bench/kvrocks` image; see the top-level README).

## What to Expect

**When the bug is present (FAIL):**
A small value written to master after a large batch does not appear on the replica within 5 seconds. The replication stream is stalled.

**When the bug is fixed (PASS):**
The small value appears on the replica within seconds, regardless of the prior batch size.

## Detailed Documentation

- [`symptom.md`](symptom.md) -- Observable behavior and error messages
- [`reproduce.md`](reproduce.md) -- Step-by-step reproduction procedure and what PASS/FAIL mean
- [`reproduce.sh`](reproduce.sh) -- The oracle (exit 0 PASS, 1 FAIL, 2 ERROR)
