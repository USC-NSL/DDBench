# Reproduce: hashicorp/raft PR#581

## Prerequisites
- Go 1.21+ installed
- hashicorp/raft checked out at the buggy version (see setup.md)

## Step 1: Create a test program

Create a Go program (`main.go`) that:
- Sets up a 7-node in-memory Raft cluster using `InmemTransport`
- Waits for a leader to be elected
- Starts a background goroutine that continuously calls `Apply()` on the leader
- Picks a specific follower as the transfer target
- Calls `LeadershipTransferToServer()` targeting that follower while writes are ongoing
- After the transfer completes, checks whether the target actually became the new leader

```go
package main

import (
    "errors"
    "fmt"
    "io"
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
    // Create 7-node cluster, start concurrent writes, transfer leadership,
    // check if target became leader.
    // See setup.sh for the full program.
}
```

## Step 2: Build the test program

```bash
cd test/
go mod init raft-transfer-test
go mod edit -replace github.com/hashicorp/raft=/path/to/raft
go mod tidy
go build -o raft-transfer-test .
```

## Step 3: Run multiple times

The bug is timing-dependent, so run multiple iterations:
```bash
FAILURES=0
for i in $(seq 1 30); do
    echo "=== Attempt $i ==="
    OUTPUT=$(timeout 60 ./raft-transfer-test 2>&1)
    if echo "$OUTPUT" | grep -q "TRANSFER_FAILED"; then
        FAILURES=$((FAILURES + 1))
        echo "Transfer failed on attempt $i"
    fi
done
echo "Failures: $FAILURES/30"
```

## Expected result (bug present)

Multiple runs will report `TRANSFER_FAILED`, indicating that the designated transfer target did not become the new leader. The target may lose the election to another node whose log is more up-to-date, or the transfer may time out entirely. Typically more than 5 out of 30 attempts will fail.

Example output:
```
Transferring leadership to node3...
TRANSFER_FAILED: Leadership went to node5 instead of node3 (writes: 42)
```

## Expected result (bug absent)

All or nearly all transfers succeed, with the designated target becoming the new leader:
```
Transferring leadership to node3...
TRANSFER_OK: Leadership transferred to node3 (writes: 38)
```
