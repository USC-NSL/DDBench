# Reproduce: hashicorp/raft #517

## Prerequisites
- Go 1.21+ installed
- hashicorp/raft checked out at the buggy version (see setup.md)

## Step 1: Create a test program

Create `main.go` that:
- Sets up a 3-node in-memory raft cluster using `InmemTransport`
- Waits for a leader to be elected
- Applies some entries to establish cluster state
- Triggers `LeadershipTransfer()` repeatedly (20 rounds)
- Applies entries between transfers to generate heartbeat traffic
- Shuts down all nodes

```go
package main

import (
    "fmt"
    "io"
    "log"
    "os"
    "sync"
    "time"

    "github.com/hashicorp/raft"
)

type MockFSM struct{}
func (m *MockFSM) Apply(l *raft.Log) interface{} { return nil }
func (m *MockFSM) Snapshot() (raft.FSMSnapshot, error) { return &MockSnapshot{}, nil }
func (m *MockFSM) Restore(r io.ReadCloser) error { return nil }

type MockSnapshot struct{}
func (m *MockSnapshot) Persist(sink raft.SnapshotSink) error {
    sink.Write([]byte("snapshot"))
    return sink.Close()
}
func (m *MockSnapshot) Release() {}

func main() {
    // Create 3-node cluster, trigger leadership transfers, detect races
    // See setup.sh for the full program
}
```

## Step 2: Build with race detector

```bash
go build -race -o raft-race-test .
```

## Step 3: Run multiple times

The data race is timing-dependent, so it may not trigger on every run:
```bash
for i in $(seq 1 30); do
    echo "=== Attempt $i ==="
    OUTPUT=$(timeout 60 ./raft-race-test 2>&1)
    if echo "$OUTPUT" | grep -q "WARNING: DATA RACE"; then
        echo "DATA RACE detected on attempt $i"
        break
    fi
done
```

## Expected result (bug present)

Some runs will trigger the Go race detector, printing output like:
```
WARNING: DATA RACE
Read at 0x00c000... by goroutine ...:
  github.com/hashicorp/raft.(*Raft).appendEntries()
      ...raft.go:...

Previous write at 0x00c000... by goroutine ...:
  github.com/hashicorp/raft.(*Raft).runCandidate()
      ...raft.go:...
```

The race is between a write in `runCandidate()` and a read in `appendEntries()`.

## Expected result (bug absent)

All runs complete without any `WARNING: DATA RACE` output from the Go race detector.
