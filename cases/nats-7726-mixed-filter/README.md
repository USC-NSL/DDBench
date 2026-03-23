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
The test `TestGenericSublistInterestBasedIntersection/PWCDoesntHideLiteral` fails because the PWC filter hides the literal filter -- intersection returns 1 instead of 2.

**When the bug is fixed (PASS):**
The test passes -- both wildcard and literal filters are correctly matched.

## Detailed Documentation

- [`symptom.md`](symptom.md) -- Observable behavior and error messages
- [`setup.md`](setup.md) -- Detailed setup instructions
- [`reproduce.md`](reproduce.md) -- Step-by-step reproduction procedure
- [`verification.md`](verification.md) -- Pass/fail verification criteria
