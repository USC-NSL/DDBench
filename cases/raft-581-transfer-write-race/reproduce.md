# Reproduce: hashicorp/raft PR#581

## Prerequisites
- Run inside `./bench.sh shell raft-581-transfer-write-race`: hashicorp/raft at the buggy commit is at `/workspace/src`, and the Go toolchain is in the image.
- The automated oracle (`bash /bench/reproduce.sh`) instead injects `/bench/inject_test.go` into package `raft` and runs it.

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
    // (sketch only; the full program is not shipped with the case)
}
```

## Step 2: Build the test program

```bash
cd test/
go mod init raft-transfer-test
go mod edit -replace github.com/hashicorp/raft=/workspace/src
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

## Oracle verdict

`./bench.sh reproduce raft-581-transfer-write-race` rebuilds the worktree and runs the oracle (`reproduce.sh`):

- **FAIL** (exit 1): at least one of 10 runs of the injected test `TestDDBenchOracleWritesDuringTransfer` fails: in a 7-node in-memory cluster, more than 1 of 50 targeted leadership transfers (each started while 16 goroutines keep calling `Apply()` on the leader) returns an error or leaves a node other than the target as leader 300 ms later; a run that otherwise fails or exceeds its 120 s timeout also counts. A worktree that does not build, or a package or injected test that does not compile (or a skipped test), is also FAIL.
- **PASS** (exit 0): all 10 runs pass, i.e. in every run at most 1 of the 50 transfers misses its target.
- **ERROR** (exit 2): `REBUILD.sh`, `raft.go` or `inject_test.go` is missing, or the test did not run because a Go module download failed (network).
