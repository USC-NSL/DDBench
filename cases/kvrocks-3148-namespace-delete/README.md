# Kvrocks #3148: NAMESPACE SET with Duplicate Token Silently Deletes Namespace

| Field | Value |
|-------|-------|
| Project | [Kvrocks](https://github.com/apache/kvrocks) |
| Issue | [#3148](https://github.com/apache/kvrocks/issues/3148) |
| Language | C++ |
| Category | Data Loss (silent namespace deletion) |

## Bug Summary

Using `NAMESPACE SET` to change a namespace's token to one already used by another namespace causes the other namespace to be silently deleted. For example, if `ns1` has `token1` and `ns2` has `token2`, running `NAMESPACE SET ns1 token2` deletes `ns2` entirely, losing all its associated data.

## Quick Start

```bash
# 1. Set up the codebase (clone, checkout buggy commit, build)
./setup.sh

# 2. Reproduce the bug and verify
./reproduce.sh
```

## Prerequisites

- Git
- C++ compiler (GCC 7+ or Clang)
- CMake 3.16+
- `redis-cli` (from redis-tools package)

## What to Expect

**When the bug is present (FAIL):**
`ns2` disappears from the namespace list after `NAMESPACE SET ns1 token2`. The namespace and all its data are lost.

**When the bug is fixed (PASS):**
The `NAMESPACE SET` command returns an error indicating the token is already in use. Both namespaces remain intact.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and error messages
- [`setup.md`](setup.md) — Detailed setup instructions
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure
- [`verification.md`](verification.md) — Pass/fail verification criteria
