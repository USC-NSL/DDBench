# Dragonfly #6614: MONITOR Inside MULTI/EXEC Causes Assertion Failure

| Field | Value |
|-------|-------|
| Project | [Dragonfly](https://github.com/dragonflydb/dragonfly) |
| Issue | [#6614](https://github.com/dragonflydb/dragonfly/issues/6614) |
| Language | C++ |
| Category | Crash (SIGABRT / assertion failure) |

## Bug Summary

Calling MONITOR twice inside a MULTI/EXEC block causes `ChangeMonitor` to add the connection twice, triggering an assertion failure (`Check failed: cc_`). The process crashes with SIGABRT.

## Quick Start

```bash
# from the repository root
./bench.sh setup dragonfly-6614-monitor-multiexec        # build image + case repository, warm caches
./bench.sh reproduce dragonfly-6614-monitor-multiexec    # FAIL (exit 1) while the bug is present
./bench.sh shell dragonfly-6614-monitor-multiexec        # explore: source at /workspace/src, oracle at /bench/reproduce.sh
```

## Prerequisites

Docker (all toolchains are in the `bug-bench/dragonfly` image; see the top-level README).

## What to Expect

**When the bug is present (FAIL):**
The Dragonfly process crashes with SIGABRT (exit code 134) when MONITOR is called twice inside MULTI/EXEC.

**When the bug is fixed (PASS):**
The command completes without crashing and the process remains alive.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and error messages
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure and what PASS/FAIL mean
- [`reproduce.sh`](reproduce.sh) — The oracle (exit 0 PASS, 1 FAIL, 2 ERROR)
