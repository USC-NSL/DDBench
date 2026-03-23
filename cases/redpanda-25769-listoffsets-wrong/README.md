# Redpanda #25769: ListOffsets Returns Incorrect Results for Compressed Batches

| Field | Value |
|-------|-------|
| Project | [Redpanda](https://github.com/redpanda-data/redpanda) |
| Issue | [#25769](https://github.com/redpanda-data/redpanda/issues/25769) |
| Language | C++ |
| Category | Data correctness (wrong offset lookup) |

## Bug Summary

The Kafka `ListOffsets` API returns incorrect offsets when querying by timestamp on topics with compressed record batches. Instead of returning the offset of the first record at or after the requested timestamp, it returns the offset at the start of the compressed batch (offset 0). This breaks any consumer using timestamp-based seeking.

## Quick Start

```bash
# 1. Clone, checkout, and build Redpanda from source
./setup.sh

# 2. Reproduce the bug and verify
./reproduce.sh
```

## Prerequisites

- git, cmake, ninja-build
- C++ compiler (clang 16+ or GCC 12+)
- Build dependencies: libboost-all-dev, ragel, libhwloc-dev, libnuma-dev, etc. (setup.sh installs them)
- Python 3 with pip (for confluent-kafka library)
- At least 16 GB RAM, 30 GB disk space
- Build time: 30-60 minutes
- No other services listening on ports 9092, 9644, or 33145

## What to Expect

**When the bug is present (FAIL):**
`ListOffsets` returns offset 0 (batch start) for all timestamp queries within a compressed batch, regardless of which record's timestamp was queried.

**When the bug is fixed (PASS):**
`ListOffsets` returns the correct per-record offset matching the queried timestamp.

## Detailed Documentation

- [`symptom.md`](symptom.md) -- Observable behavior and error messages
- [`setup.md`](setup.md) -- Detailed setup instructions
- [`reproduce.md`](reproduce.md) -- Step-by-step reproduction procedure
- [`verification.md`](verification.md) -- Pass/fail verification criteria
