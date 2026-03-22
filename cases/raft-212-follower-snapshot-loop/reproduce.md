# Reproduce: hashicorp/raft #212

## Prerequisites
Built raft library on the buggy version (see setup.md).

## Step 1: Write a test program

Create `repro_test.go`:
```go
package raft_test

import (
    "fmt"
    "testing"
    "time"

    "github.com/hashicorp/raft"
)

func TestSnapshotInstallLoop(t *testing.T) {
    // Create 3-node cluster with in-memory transport
    cluster := raft.MakeCluster(3, t, nil)
    defer cluster.Close()

    leader := cluster.Leader()
    followers := cluster.GetInState(raft.Follower)
    if len(followers) < 2 {
        t.Fatal("expected at least 2 followers")
    }

    // Apply some log entries
    for i := 0; i < 100; i++ {
        future := leader.Apply([]byte(fmt.Sprintf("msg-%d", i)), 5*time.Second)
        if err := future.Error(); err != nil {
            t.Fatalf("apply failed: %v", err)
        }
    }

    // Take a snapshot and compact the log
    future := leader.Snapshot()
    if err := future.Error(); err != nil {
        t.Fatalf("snapshot failed: %v", err)
    }

    // Disconnect one follower
    targetFollower := followers[0]
    cluster.Disconnect(targetFollower.String())

    // Apply more entries while follower is disconnected
    for i := 100; i < 300; i++ {
        future := leader.Apply([]byte(fmt.Sprintf("msg-%d", i)), 5*time.Second)
        if err := future.Error(); err != nil {
            t.Fatalf("apply failed: %v", err)
        }
    }

    // Take another snapshot and compact
    future = leader.Snapshot()
    if err := future.Error(); err != nil {
        t.Fatalf("snapshot failed: %v", err)
    }

    // Reconnect the follower
    cluster.Reconnect(targetFollower.String())

    // Wait and check if follower catches up
    time.Sleep(30 * time.Second)

    // Check follower's last index
    leaderLast := leader.LastIndex()
    followerLast := targetFollower.LastIndex()

    if followerLast < leaderLast-5 {
        t.Fatalf("FAIL: Follower stuck — leader at %d, follower at %d", leaderLast, followerLast)
    }
    t.Logf("PASS: Follower caught up — leader at %d, follower at %d", leaderLast, followerLast)
}
```

## Step 2: Run the test

```bash
go test -v -run TestSnapshotInstallLoop -timeout 120s
```

## Expected result (bug present)
The test times out or fails with the follower's last index far behind the leader. Logs show repeated snapshot install failures in a loop.
