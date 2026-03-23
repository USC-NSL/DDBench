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
# 1. Set up the codebase (clone, checkout buggy commit, build)
./setup.sh

# 2. Reproduce the bug and verify
./reproduce.sh
```

## Prerequisites

- Git
- Go 1.22+ (expected at /usr/local/go/bin/go)

## What to Expect

**When the bug is present (FAIL):**
The test outputs `WARNING: DATA RACE` showing a write in `embed.(*Etcd).Close()` racing with a read in `embed.(*Etcd).errHandler()`. The test fails with `race detected during execution of test`.

**When the bug is fixed (PASS):**
The test completes without any race warnings across 10 consecutive runs.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and error messages
- [`setup.md`](setup.md) — Detailed setup instructions
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure
- [`verification.md`](verification.md) — Pass/fail verification criteria
