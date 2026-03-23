# NATS Server #7852: Single FilterSubject Performance Regression

| Field | Value |
|-------|-------|
| Project | [NATS Server](https://github.com/nats-io/nats-server) |
| Issue | [#7852](https://github.com/nats-io/nats-server/issues/7852) |
| Language | Go |
| Category | Performance regression (unnecessary filter overhead) |

## Bug Summary

When a JetStream consumer is created with a single subject in the `FilterSubjects` field that matches all subjects in the stream, message delivery performance degrades by more than 20%. The `o.filters` map is non-nil even with a single filter subject, forcing the slower `LoadNextMsgMulti` code path instead of the optimized single-filter path.

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
The test `TestJetStreamConsumerSingleFilterSubjectInFilterSubjects` fails because a single-entry `FilterSubjects` configuration takes the slower multi-filter code path.

**When the bug is fixed (PASS):**
The test passes -- a single-entry `FilterSubjects` is optimized to use the fast single-filter code path.

## Detailed Documentation

- [`symptom.md`](symptom.md) -- Observable behavior and error messages
- [`setup.md`](setup.md) -- Detailed setup instructions
- [`reproduce.md`](reproduce.md) -- Step-by-step reproduction procedure
- [`verification.md`](verification.md) -- Pass/fail verification criteria
