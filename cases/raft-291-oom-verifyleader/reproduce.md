# Reproduce: hashicorp/raft #291

## Prerequisites
Built raft library on the buggy version (see setup.md).

## Step 1: Write a test program

Create `repro_oom_test.go`:
```go
package raft_test

import (
    "fmt"
    "runtime"
    "testing"
    "time"

    "github.com/hashicorp/raft"
)

func TestVerifyLeaderOOM(t *testing.T) {
    // Create 3-node cluster
    cluster := raft.MakeCluster(3, t, nil)
    defer cluster.Close()

    leader := cluster.Leader()
    followers := cluster.GetInState(raft.Follower)
    if len(followers) < 2 {
        t.Fatal("expected at least 2 followers")
    }

    // Apply some entries to establish leadership
    for i := 0; i < 10; i++ {
        future := leader.Apply([]byte(fmt.Sprintf("msg-%d", i)), 5*time.Second)
        if err := future.Error(); err != nil {
            t.Fatalf("apply failed: %v", err)
        }
    }

    // Disconnect one follower (simulate failure)
    cluster.Disconnect(followers[0].String())

    // Record initial memory
    var m1, m2 runtime.MemStats
    runtime.GC()
    runtime.ReadMemStats(&m1)

    // Repeatedly call VerifyLeader
    for i := 0; i < 10000; i++ {
        future := leader.VerifyLeader()
        // Don't wait for the future — just fire and forget
        _ = future
        if i%1000 == 0 {
            runtime.GC()
            runtime.ReadMemStats(&m2)
            t.Logf("Iteration %d: HeapInuse=%dMB", i, m2.HeapInuse/1024/1024)
        }
    }

    // Wait for some futures to time out
    time.Sleep(10 * time.Second)

    runtime.GC()
    runtime.ReadMemStats(&m2)

    growth := int64(m2.HeapInuse) - int64(m1.HeapInuse)
    t.Logf("Memory growth: %dMB (from %dMB to %dMB)",
        growth/1024/1024, m1.HeapInuse/1024/1024, m2.HeapInuse/1024/1024)

    if growth > 50*1024*1024 { // >50MB growth
        t.Fatalf("FAIL: Memory leak detected — grew by %dMB", growth/1024/1024)
    }
    t.Log("PASS: Memory growth within bounds")
}
```

## Step 2: Run the test

```bash
go test -v -run TestVerifyLeaderOOM -timeout 120s
```

## Expected result (bug present)
Memory grows significantly (50MB+) over the course of 10,000 VerifyLeader calls with a disconnected follower. The test fails with `"Memory leak detected"`.
