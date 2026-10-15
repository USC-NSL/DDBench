# Reproduce: hashicorp/raft #358

## Step 1: Set up a Raft cluster that triggers snapshots

The bug occurs when a snapshot's last included index is less than the log store's first index. This can happen when:
- A node joins a cluster and receives a snapshot
- The node then takes its own snapshot
- The compaction step uses the old snapshot's index

```go
// Create a test that triggers the condition:
package raft_test

import (
    "testing"
    "time"

    "github.com/hashicorp/raft"
)

func TestSnapshotNegativeRange(t *testing.T) {
    // Create a 3-node cluster
    cluster := raft.MakeClusterCustom(t, &raft.MakeClusterOpts{
        Peers:          3,
        Bootstrap:      true,
        Conf:           raft.DefaultConfig(),
    })
    defer cluster.Close()

    leader := cluster.Leader()

    // Apply enough entries to trigger snapshots
    for i := 0; i < 200; i++ {
        leader.Apply([]byte("data"), 5*time.Second)
    }

    // Force snapshot
    f := leader.Snapshot()
    if f.Error() != nil {
        t.Fatal(f.Error())
    }

    // Apply more entries
    for i := 0; i < 200; i++ {
        leader.Apply([]byte("more-data"), 5*time.Second)
    }

    // Force another snapshot — watch for "Compacting logs from X to Y" where X > Y
    f = leader.Snapshot()
    if f.Error() != nil {
        t.Fatal(f.Error())
    }
}
```

## Step 2: Run the test and observe logs

```bash
go test -v -run TestSnapshotNegativeRange ./... 2>&1 | grep "Compacting logs"
```

## Expected result (bug present)
Log output shows "Compacting logs from X to Y" where X > Y (e.g., "from 26108 to 6079"), indicating an invalid negative range passed to `DeleteRange`.

## Oracle verdict

`./bench.sh reproduce raft-358-negative-log-range` rebuilds the worktree and runs the oracle (`reproduce.sh`):

- **FAIL** (exit 1): the injected test `TestDDBenchOracleCompactLogsRange` fails: when `compactLogs(50)` runs on a log store holding entries 100–200 (`TrailingLogs = 0`), the log store's `DeleteRange` is called with `min > max`. A worktree that does not build, or a package or injected test that does not compile (or a skipped test), is also FAIL.
- **PASS** (exit 0): the injected test passes within its 30 s timeout: `DeleteRange` is never called with `min > max`.
- **ERROR** (exit 2): `REBUILD.sh` or `raft.go` is missing (the case is not set up), or the test did not run because a Go module download failed (network).
