# NATS Server #7760: Consumer Filter Lost After Leader Step-Down

| Field | Value |
|-------|-------|
| Project | [NATS Server](https://github.com/nats-io/nats-server) |
| Issue | [#7760](https://github.com/nats-io/nats-server/issues/7760) |
| Language | Go |
| Category | Data loss (consumer filter desync after leader step-down) |

## Bug Summary

After editing a consumer's filter subjects and then triggering a leader step-down on an interest-based replicated stream (R5), the consumer stops matching messages. The internal sublist is only updated on the consumer leader but not replicated to followers. After a step-down, the new leader has a stale (empty) sublist, causing all message deliveries to time out.

## Quick Start

```bash
# from the repository root
./bench.sh setup nats-7760-filter-stepdown        # build image + case repository, warm caches
./bench.sh reproduce nats-7760-filter-stepdown    # FAIL (exit 1) while the bug is present
./bench.sh shell nats-7760-filter-stepdown        # explore: source at /workspace/src, oracle at /bench/reproduce.sh
```

## Prerequisites

Docker (all toolchains are in the `bug-bench/nats` image; see the top-level README).

## Build Notes

- The `nats` CLI (pinned) is preinstalled in the image, outside the worktree; the oracle drives a live cluster with it.

## What to Expect

**When the bug is present (FAIL):**
After editing the consumer filter and stepping down the leader, `nats consumer next` times out -- the consumer cannot match any messages.

**When the bug is fixed (PASS):**
The consumer receives the published message normally after the leader step-down.

## Detailed Documentation

- [`symptom.md`](symptom.md) -- Observable behavior and error messages
- [`reproduce.md`](reproduce.md) -- Step-by-step reproduction procedure and what PASS/FAIL mean
- [`reproduce.sh`](reproduce.sh) -- The oracle (exit 0 PASS, 1 FAIL, 2 ERROR)
