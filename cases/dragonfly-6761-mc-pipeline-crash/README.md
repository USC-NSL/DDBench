# Dragonfly #6761: Memcached Pipeline with VERSION/STATS Causes Crash

| Field | Value |
|-------|-------|
| Project | [Dragonfly](https://github.com/dragonflydb/dragonfly) |
| Issue | [#6761](https://github.com/dragonflydb/dragonfly/issues/6761) |
| Language | C++ |
| Category | Crash (SIGABRT / unhandled WOULD_BLOCK) |

## Bug Summary

When using the memcached protocol, sending pipelined commands where a `get` precedes a `version` or `stats` command causes a crash. The `version` and `stats` commands return `WOULD_BLOCK` which is not properly handled in the pipeline batch execution path (`Connection::ExecuteMCBatch()`).

## Quick Start

```bash
# from the repository root
./bench.sh setup dragonfly-6761-mc-pipeline-crash        # build image + case repository, warm caches
./bench.sh reproduce dragonfly-6761-mc-pipeline-crash    # FAIL (exit 1) while the bug is present
./bench.sh shell dragonfly-6761-mc-pipeline-crash        # explore: source at /workspace/src, oracle at /bench/reproduce.sh
```

## Prerequisites

Docker (all toolchains are in the `bug-bench/dragonfly` image; see the top-level README).

## What to Expect

**When the bug is present (FAIL):**
The Dragonfly process crashes with SIGABRT when pipelined memcached commands include VERSION or STATS after a GET.

**When the bug is fixed (PASS):**
The pipelined commands complete normally and the process remains alive.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and error messages
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure and what PASS/FAIL mean
- [`reproduce.sh`](reproduce.sh) — The oracle (exit 0 PASS, 1 FAIL, 2 ERROR)
