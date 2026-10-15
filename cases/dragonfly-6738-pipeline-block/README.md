# Dragonfly #6738: Replies Held Back Behind a Pipelined Blocking Command

| Field | Value |
|-------|-------|
| Project | [Dragonfly](https://github.com/dragonflydb/dragonfly) |
| Issue | [#6738](https://github.com/dragonflydb/dragonfly/issues/6738) |
| Language | C++ |
| Category | Liveness / latency (replies delayed on pipelined connections) |

## Bug Summary

When a client pipelines a blocking list command (`BLPOP`, `BRPOPLPUSH`, ...) behind other commands on one connection, it receives the replies to those earlier commands only when the blocking command completes or times out. Queue workers that pipeline several `BRPOPLPUSH` calls therefore receive a pushed job only after their other pipelined pops time out. The issue was first reported as "`BRPOPLPUSH` not woken by `RPUSH` inside a Lua script" (Bull/n8n); the push was in fact delivered, and the reply carrying it was held back on the worker's pipelined connection.

## Quick Start

```bash
# From the repository root
./bench.sh setup dragonfly-6738-pipeline-block       # image, truncated case repository, build, dependency warm-up
./bench.sh reproduce dragonfly-6738-pipeline-block   # run the oracle: exit 0 PASS, 1 FAIL, 2 ERROR
./bench.sh shell dragonfly-6738-pipeline-block       # interactive shell in /workspace/src; rerun with: bash /bench/reproduce.sh
```

Prerequisites: Docker. The compiler toolchain, `redis-cli` and `python3` are in the `bug-bench/dragonfly` image.

## What to Expect

The oracle starts Dragonfly (`--proactor_threads 2`) and sends two pipelines, each on its own connection:

1. `SET mykey myval`, `PING`, `BLPOP nolist 5`: it measures when the first reply arrives.
2. Three `BRPOPLPUSH src dst 5`; one second later a second client runs `RPUSH src hello`: it measures when the reply carrying `hello` arrives after the push.

**When the bug is present (FAIL):**
The `SET`/`PING` replies arrive after about 5 s, when `BLPOP` times out. The `hello` reply arrives about 10 s after the push, once the other two pipelined pops have timed out.

**When the bug is fixed (PASS):**
Both replies arrive within milliseconds (deadlines: 2.0 s and 2.5 s).

## Detailed Documentation

- [`symptom.md`](symptom.md): observable behavior and error messages
- [`reproduce.md`](reproduce.md): step-by-step reproduction procedure and what PASS/FAIL mean
- [`reproduce.sh`](reproduce.sh): the oracle (exit 0 PASS, 1 FAIL, 2 ERROR)
