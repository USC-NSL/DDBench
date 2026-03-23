# etcd #20893: --force-new-cluster Does Not Remove Learner Members

| Field | Value |
|-------|-------|
| Project | [etcd](https://github.com/etcd-io/etcd) |
| Issue | [#20893](https://github.com/etcd-io/etcd/issues/20893) |
| Language | Go |
| Category | Cluster recovery (stale learner member) |

## Bug Summary

When using `--force-new-cluster` to recover a single-node cluster from a snapshot, learner members are not removed from the member list. The recovered cluster still shows the learner as a member even though `--force-new-cluster` should clean up all non-self members.

## Quick Start

```bash
# 1. Set up the codebase (clone, checkout buggy commit, build)
./setup.sh

# 2. Reproduce the bug and verify
./reproduce.sh
```

## Prerequisites

- Git
- Go 1.22+ (expected at /usr/local/go/bin/go)

## What to Expect

**When the bug is present (FAIL):**
After restarting m1 with `--force-new-cluster`, `member list` still shows the learner member alongside m1.

**When the bug is fixed (PASS):**
After restarting m1 with `--force-new-cluster`, `member list` shows only m1.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and error messages
- [`setup.md`](setup.md) — Detailed setup instructions
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure
- [`verification.md`](verification.md) — Pass/fail verification criteria
