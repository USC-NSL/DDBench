# raft-rs-221-campaign-conf-change

Bug case from [tikv/raft-rs#221](https://github.com/tikv/raft-rs/issues/221).

## Quick start

```bash
cd cases/raft-rs-221-campaign-conf-change/
./setup.sh       # clone, checkout buggy commit, build test harness
./reproduce.sh   # inject test, run → PASS/FAIL
```

## Bug summary

A node receiving `MsgTimeoutNow` (leader transfer) campaigns immediately without checking for pending unapplied configuration changes. If a `RemoveNode` entry is committed but not yet applied, the node starts an election with a stale voter set, leading to incorrect vote counting and potential election failure or split-brain.
