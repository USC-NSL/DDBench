# Reproduce: hashicorp/raft #268

## Prerequisites
- Run inside `./bench.sh shell raft-268-shutdown-deadlock`: hashicorp/raft at the buggy commit is at `/workspace/src`, and the Go toolchain is in the image.
- Build the program in its own module that points at that source:
  ```bash
  mkdir -p /tmp/raft-deadlock-test && cd /tmp/raft-deadlock-test
  go mod init raft-deadlock-test
  go mod edit -replace github.com/hashicorp/raft=/workspace/src
  # create main.go (below), then:
  go mod tidy
  ```
- The automated oracle (`bash /bench/reproduce.sh`) builds its own harness, `/bench/test_main.go`, the same way.

## Step 1: Create a test program

Create `main.go`:
```go
package main

import (
    "fmt"
    "io"
    "log"
    "os"
    "time"

    "github.com/hashicorp/raft"
)

// Minimal FSM implementation
type MockFSM struct{}

func (m *MockFSM) Apply(l *raft.Log) interface{} { return nil }
func (m *MockFSM) Snapshot() (raft.FSMSnapshot, error) {
    // Simulate a slow snapshot to increase the race window
    time.Sleep(100 * time.Millisecond)
    return &MockSnapshot{}, nil
}
func (m *MockFSM) Restore(r io.ReadCloser) error { return nil }

type MockSnapshot struct{}

func (m *MockSnapshot) Persist(sink raft.SnapshotSink) error {
    sink.Write([]byte("snapshot"))
    return sink.Close()
}
func (m *MockSnapshot) Release() {}

func main() {
    config := raft.DefaultConfig()
    config.LocalID = "node1"
    config.SnapshotThreshold = 1
    config.SnapshotInterval = 100 * time.Millisecond
    config.LogOutput = os.Stderr

    store := raft.NewInmemStore()
    snapStore := raft.NewInmemSnapshotStore()
    transport, err := raft.NewTCPTransport("127.0.0.1:0", nil, 3, 10*time.Second, os.Stderr)
    if err != nil {
        log.Fatal(err)
    }

    r, err := raft.NewRaft(config, &MockFSM{}, store, store, snapStore, transport)
    if err != nil {
        log.Fatal(err)
    }

    // Bootstrap as single-node cluster
    configuration := raft.Configuration{
        Servers: []raft.Server{
            {ID: "node1", Address: transport.LocalAddr()},
        },
    }
    r.BootstrapCluster(configuration)

    // Wait for leader election
    time.Sleep(3 * time.Second)

    // Apply some entries to trigger snapshot threshold
    for i := 0; i < 10; i++ {
        r.Apply([]byte(fmt.Sprintf("entry-%d", i)), 5*time.Second)
    }

    // Now shutdown — this may deadlock if a snapshot is in progress
    fmt.Println("Calling Shutdown()...")
    done := make(chan struct{})
    go func() {
        future := r.Shutdown()
        if err := future.Error(); err != nil {
            fmt.Printf("Shutdown error: %v\n", err)
        }
        close(done)
    }()

    select {
    case <-done:
        fmt.Println("Shutdown completed successfully")
    case <-time.After(30 * time.Second):
        fmt.Println("DEADLOCK: Shutdown() has been blocked for 30 seconds")
        os.Exit(1)
    }
}
```

## Step 2: Run the test

```bash
go run main.go
```

## Step 3: Run multiple times

The deadlock is a race condition, so it may not trigger on every run:
```bash
for i in $(seq 1 20); do
    echo "=== Attempt $i ==="
    timeout 35 go run main.go
    EXIT_CODE=$?
    if [ $EXIT_CODE -ne 0 ]; then
        echo "DEADLOCK detected on attempt $i"
        break
    fi
done
```

## Expected result (bug present)

Some runs will print "DEADLOCK: Shutdown() has been blocked for 30 seconds" and exit with code 1. The deadlock occurs when `takeSnapshot()` sends a request to `configurationsCh` right as the main Raft loop is shutting down.

## Expected result (bug absent)

All runs complete with "Shutdown completed successfully" within a few seconds.

## Oracle verdict

`./bench.sh reproduce raft-268-shutdown-deadlock` rebuilds the worktree and runs the oracle (`reproduce.sh`):

- **FAIL** (exit 1): in any of 50 attempts, `Shutdown()` of a single-node cluster (snapshot threshold 1, 10 ms snapshot interval, FSM snapshots slowed to 200 ms, `GOMAXPROCS(1)`), called shortly after five `Apply()` calls while an FSM snapshot may be in flight, does not return within 10 s, or the harness as a whole runs longer than 900 s. A worktree that does not build, a harness (`test_main.go`) that cannot be resolved or compiled against the worktree's raft package, or a node that does not start or become leader within 5 s, is also FAIL.
- **PASS** (exit 0): all 50 attempts shut down within 10 s and at least one FSM snapshot was taken.
- **ERROR** (exit 2): `REBUILD.sh`, `raft.go` or `test_main.go` is missing, the harness's Go modules cannot be downloaded (network), the harness cannot create its TCP transport, no FSM snapshot was ever taken (trigger not exercised), or the harness exits with an unexpected code.
