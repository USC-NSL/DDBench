# NATS Server #7726: Mixed Wildcard/Literal Filter Subjects Fail to Deliver

| Field | Value |
|-------|-------|
| Project | [NATS Server](https://github.com/nats-io/nats-server) |
| Issue | [#7726](https://github.com/nats-io/nats-server/issues/7726) |
| Language | Go |
| Category | Incorrect behavior (message delivery failure) |

## Bug Summary

The subject tree intersection logic does not handle mixed wildcard/literal combinations correctly. When a consumer has both a wildcard filter (e.g., `one.*.six`) and a literal filter (e.g., `one.two.seven`), the intersection algorithm incorrectly concludes that the literal subject does not match, because the wildcard path subsumes it in the tree structure.

## Quick Start

```bash
# from the repository root
./bench.sh setup nats-7726-mixed-filter        # build image + case repository, warm caches
./bench.sh reproduce nats-7726-mixed-filter    # FAIL (exit 1) while the bug is present
./bench.sh shell nats-7726-mixed-filter        # explore: source at /workspace/src, oracle at /bench/reproduce.sh
```

## Prerequisites

Docker (all toolchains are in the `bug-bench/nats` image; see the top-level README).

## Build Notes

- The `nats` CLI used by the manual procedure is preinstalled (pinned) in the image.

## What to Expect

**When the bug is present (FAIL):**
The test `TestGenericSublistInterestBasedIntersection/PWCDoesntHideLiteral` fails because the PWC filter hides the literal filter -- intersection returns 1 instead of 2.

**When the bug is fixed (PASS):**
The test passes -- both wildcard and literal filters are correctly matched.

## Detailed Documentation

- [`symptom.md`](symptom.md) -- Observable behavior and error messages
- [`reproduce.md`](reproduce.md) -- Step-by-step reproduction procedure and what PASS/FAIL mean
- [`reproduce.sh`](reproduce.sh) -- The oracle (exit 0 PASS, 1 FAIL, 2 ERROR)
