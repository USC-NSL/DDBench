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
# from the repository root
./bench.sh setup kvrocks-3148-namespace-delete        # build image + case repository, warm caches
./bench.sh reproduce kvrocks-3148-namespace-delete    # FAIL (exit 1) while the bug is present
./bench.sh shell kvrocks-3148-namespace-delete        # explore: source at /workspace/src, oracle at /bench/reproduce.sh
```

## Prerequisites

Docker (all toolchains are in the `bug-bench/kvrocks` image; see the top-level README).

## What to Expect

**When the bug is present (FAIL):**
`ns2` disappears from the namespace list after `NAMESPACE SET ns1 token2`. The namespace and all its data are lost.

**When the bug is fixed (PASS):**
The `NAMESPACE SET` command returns an error indicating the token is already in use. Both namespaces remain intact.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and error messages
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure and what PASS/FAIL mean
- [`reproduce.sh`](reproduce.sh) — The oracle (exit 0 PASS, 1 FAIL, 2 ERROR)
