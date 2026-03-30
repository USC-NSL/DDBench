# ZooKeeper #4846: Fuzzy Snapshot ACL Reference Error

| Field | Value |
|-------|-------|
| Project | [ZooKeeper](https://github.com/apache/zookeeper) |
| Issue | [ZOOKEEPER-4846](https://issues.apache.org/jira/browse/ZOOKEEPER-4846) |
| Language | Java |
| Category | Crash / data corruption (fuzzy snapshot deserialization) |

## Bug Summary

During fuzzy snapshot serialization, the ACL cache is serialized before znodes. A race condition can cause a node to be deleted (removing its ACL from the cache), then recreated with the same ACL, and finally serialized referencing an ACL that was already purged. On restart, the server crashes with a fatal RuntimeException when trying to access the missing ACL reference.

## Quick Start

```bash
# 1. Set up the codebase (clone, checkout buggy commit, build)
./setup.sh

# 2. Reproduce the bug and verify
./reproduce.sh
```

## Prerequisites

- Java 11 (JDK)
- Maven 3.8+
- Git

## What to Expect

**When the bug is present (FAIL):**
The regression test fails because creating a child node throws a RuntimeException -- the parent node's ACL reference was removed from the cache (simulating the fuzzy snapshot race), and `createNode` does not defensively recover the missing ACL.

**When the bug is fixed (PASS):**
The test passes because `createNode` defensively recovers the missing ACL reference during `fastForwardFromEdits`, allowing the child node to be created successfully.

## Detailed Documentation

- [`symptom.md`](symptom.md) -- Observable behavior and error messages
- [`setup.md`](setup.md) -- Detailed setup instructions
- [`reproduce.md`](reproduce.md) -- Step-by-step reproduction procedure
- [`verification.md`](verification.md) -- Pass/fail verification criteria
