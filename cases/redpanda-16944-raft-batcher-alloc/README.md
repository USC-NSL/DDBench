# Redpanda #16944: Oversized Allocation in Raft Replicate Batcher

| Field | Value |
|-------|-------|
| Project | [Redpanda](https://github.com/redpanda-data/redpanda) |
| Issue | [#16944](https://github.com/redpanda-data/redpanda/issues/16944) |
| Language | C++ |
| Category | Performance regression (oversized memory allocation) |

## Bug Summary

Under high write throughput, the `raft::replicate_batcher` triggers Seastar's oversized allocation warning. The batcher's internal `std::vector` grows via capacity-doubling, eventually requiring a single contiguous allocation exceeding 128 KB. This causes log spam, potential memory fragmentation, and latency spikes.

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
- At least 16 GB RAM, 30 GB disk space
- Build time: 30-60 minutes
- No other services listening on ports 9092, 9644, or 33145

## What to Expect

**When the bug is present (FAIL):**
Redpanda logs contain "oversized allocation" warnings referencing `raft::replicate_batcher::flush` during sustained high-throughput writes.

**When the bug is fixed (PASS):**
No oversized allocation warnings appear under the same workload.

## Detailed Documentation

- [`symptom.md`](symptom.md) -- Observable behavior and error messages
- [`setup.md`](setup.md) -- Detailed setup instructions
- [`reproduce.md`](reproduce.md) -- Step-by-step reproduction procedure
- [`verification.md`](verification.md) -- Pass/fail verification criteria
