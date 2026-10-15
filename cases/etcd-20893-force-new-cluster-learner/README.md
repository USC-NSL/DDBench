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
# from the repository root
./bench.sh setup etcd-20893-force-new-cluster-learner        # build image + case repository, warm caches
./bench.sh reproduce etcd-20893-force-new-cluster-learner    # FAIL (exit 1) while the bug is present
./bench.sh shell etcd-20893-force-new-cluster-learner        # explore: source at /workspace/src, oracle at /bench/reproduce.sh
```

## Prerequisites

Docker (all toolchains are in the `bug-bench/etcd` image; see the top-level README).

## Build Notes

- `make build` produces `bin/etcd`, `bin/etcdctl` and `bin/etcdutl`.

## What to Expect

**When the bug is present (FAIL):**
After restarting m1 with `--force-new-cluster`, `member list` still shows the learner member alongside m1.

**When the bug is fixed (PASS):**
After restarting m1 with `--force-new-cluster`, `member list` shows only m1.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and error messages
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure and what PASS/FAIL mean
- [`reproduce.sh`](reproduce.sh) — The oracle (exit 0 PASS, 1 FAIL, 2 ERROR)
