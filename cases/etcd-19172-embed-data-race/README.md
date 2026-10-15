# etcd #19172: Data Race Between Etcd.Close() and Etcd.errHandler()

| Field | Value |
|-------|-------|
| Project | [etcd](https://github.com/etcd-io/etcd) |
| Issue | [#19172](https://github.com/etcd-io/etcd/issues/19172) |
| Language | Go |
| Category | Race condition (data race) |

## Bug Summary

A data race is detected between `Etcd.Close()` and `Etcd.errHandler()` when running the embedded etcd integration tests with the race detector enabled. One goroutine writes a field in `Close()` while another goroutine reads it in `errHandler()`, triggering a `WARNING: DATA RACE` failure.

## Quick Start

```bash
# from the repository root
./bench.sh setup etcd-19172-embed-data-race        # build image + case repository, warm caches
./bench.sh reproduce etcd-19172-embed-data-race    # FAIL (exit 1) while the bug is present
./bench.sh shell etcd-19172-embed-data-race        # explore: source at /workspace/src, oracle at /bench/reproduce.sh
```

## Prerequisites

Docker (all toolchains are in the `bug-bench/etcd` image; see the top-level README).

## What to Expect

**When the bug is present (FAIL):**
The test outputs `WARNING: DATA RACE` showing a write in `embed.(*Etcd).Close()` racing with a read in `embed.(*Etcd).errHandler()`. The test fails with `race detected during execution of test`.

**When the bug is fixed (PASS):**
The test completes without any race warnings across 10 consecutive runs.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and error messages
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure and what PASS/FAIL mean
- [`reproduce.sh`](reproduce.sh) — The oracle (exit 0 PASS, 1 FAIL, 2 ERROR)
