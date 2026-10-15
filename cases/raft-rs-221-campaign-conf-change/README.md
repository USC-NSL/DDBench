# raft-rs-221-campaign-conf-change

Bug case from [tikv/raft-rs#221](https://github.com/tikv/raft-rs/issues/221).

## Quick Start

```bash
# from the repository root
./bench.sh setup raft-rs-221-campaign-conf-change        # build image + case repository, warm caches
./bench.sh reproduce raft-rs-221-campaign-conf-change    # FAIL (exit 1) while the bug is present
./bench.sh shell raft-rs-221-campaign-conf-change        # explore: source at /workspace/src, oracle at /bench/reproduce.sh
```

## Prerequisites

Docker (all toolchains are in the `bug-bench/raft-rs` image; see the top-level README).

## Bug summary

A node receiving `MsgTimeoutNow` (leader transfer) campaigns immediately without checking for pending unapplied configuration changes. If a `RemoveNode` entry is committed but not yet applied, the node starts an election with a stale voter set, leading to incorrect vote counting and potential election failure or split-brain.
