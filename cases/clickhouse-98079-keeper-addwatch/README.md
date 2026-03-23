# ClickHouse #98079: Keeper Disconnects Client on addWatch Request

| Field | Value |
|-------|-------|
| Project | [ClickHouse](https://github.com/ClickHouse/ClickHouse) |
| Issue | [#98079](https://github.com/ClickHouse/ClickHouse/issues/98079) |
| Language | C++ |
| Category | Protocol incompatibility (client disconnect) |

## Bug Summary

When a ZooKeeper client sends an `addWatch` request (from ZooKeeper 3.6+ protocol) to ClickHouse Keeper, the Keeper immediately disconnects the client. This breaks applications using Apache Curator's CuratorCache, which relies on persistent/recursive watches via the `addWatch` API. The `addWatch` opcode is not properly handled by the Keeper protocol implementation.

## Quick Start

```bash
# 1. Clone, checkout, build ClickHouse Keeper, and download ZooKeeper tools
./setup.sh

# 2. Reproduce the bug and verify
./reproduce.sh
```

## Prerequisites

- git, cmake, ninja-build
- C++ compiler (clang 14+ or GCC 11+)
- Java 11+ (for zkCli.sh)
- netcat (`nc`) for health checks
- At least 16 GB RAM, 30 GB disk space
- Build time: 30-90 minutes

## What to Expect

**When the bug is present (FAIL):**
The Keeper disconnects the client upon receiving an `addWatch` request; the connection is lost.

**When the bug is fixed (PASS):**
The `addWatch` request is handled correctly and the watch is established successfully.

## Detailed Documentation

- [`symptom.md`](symptom.md) -- Observable behavior and error messages
- [`setup.md`](setup.md) -- Detailed setup instructions
- [`reproduce.md`](reproduce.md) -- Step-by-step reproduction procedure
- [`verification.md`](verification.md) -- Pass/fail verification criteria
