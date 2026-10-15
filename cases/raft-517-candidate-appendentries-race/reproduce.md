# Reproduce: hashicorp/raft #517

## Prerequisites
- Run inside `./bench.sh shell raft-517-candidate-appendentries-race`: hashicorp/raft at the buggy commit is at `/workspace/src`, and the Go toolchain is in the image.
- Build the program in its own module that points at that source:
  ```bash
  mkdir -p /tmp/raft-race-test && cd /tmp/raft-race-test
  go mod init raft-race-test
  go mod edit -replace github.com/hashicorp/raft=/workspace/src
  # create main.go (below), then:
  go mod tidy
  ```
- The automated oracle (`bash /bench/reproduce.sh`) instead injects `/bench/inject_test.go` into package `raft` and runs it under the race detector.

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
    // (sketch only; the full program is not shipped with the case)
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

## Oracle verdict

`./bench.sh reproduce raft-517-candidate-appendentries-race` rebuilds the worktree and runs the oracle (`reproduce.sh`):

- **FAIL** (exit 1): in any of 5 runs of the injected test `TestDDBenchOracleCandidateAppendEntriesRace` under the Go race detector (five 3-node TCP-transport clusters, 200 leadership transfers each under continuous writes), the race detector reports a data race, or the test fails or exceeds its 120 s timeout. A worktree that does not build, or a package or injected test that does not compile (or a skipped test), is also FAIL.
- **PASS** (exit 0): the test runs and passes in all 5 runs with no data race reported.
- **ERROR** (exit 2): `REBUILD.sh`, `raft.go` or `inject_test.go` is missing, or the test did not run because a Go module download failed (network).
