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
# from the repository root
./bench.sh setup nats-7852-filter-perf        # build image + case repository, warm caches
./bench.sh reproduce nats-7852-filter-perf    # FAIL (exit 1) while the bug is present
./bench.sh shell nats-7852-filter-perf        # explore: source at /workspace/src, oracle at /bench/reproduce.sh
```

## Prerequisites

Docker (all toolchains are in the `bug-bench/nats` image; see the top-level README).

## Build Notes

- The `nats` CLI used by the manual benchmark is preinstalled (pinned) in the image.

## What to Expect

**When the bug is present (FAIL):**
The test `TestJetStreamConsumerSingleFilterSubjectInFilterSubjects` fails because a single-entry `FilterSubjects` configuration takes the slower multi-filter code path.

**When the bug is fixed (PASS):**
The test passes -- a single-entry `FilterSubjects` is optimized to use the fast single-filter code path.

## Detailed Documentation

- [`symptom.md`](symptom.md) -- Observable behavior and error messages
- [`reproduce.md`](reproduce.md) -- Step-by-step reproduction procedure and what PASS/FAIL mean
- [`reproduce.sh`](reproduce.sh) -- The oracle (exit 0 PASS, 1 FAIL, 2 ERROR)
