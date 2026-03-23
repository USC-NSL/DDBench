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
# 1. Set up the codebase (clone, checkout buggy version, build, install nats CLI)
./setup.sh

# 2. Reproduce the bug and verify
./reproduce.sh
```

## Prerequisites

- Git
- Go 1.22+ (expected at /usr/local/go/bin/go)

## What to Expect

**When the bug is present (FAIL):**
After editing the consumer filter and stepping down the leader, `nats consumer next` times out -- the consumer cannot match any messages.

**When the bug is fixed (PASS):**
The consumer receives the published message normally after the leader step-down.

## Detailed Documentation

- [`symptom.md`](symptom.md) -- Observable behavior and error messages
- [`setup.md`](setup.md) -- Detailed setup instructions
- [`reproduce.md`](reproduce.md) -- Step-by-step reproduction procedure
- [`verification.md`](verification.md) -- Pass/fail verification criteria
