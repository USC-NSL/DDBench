# Test Output

Obtained by running `go test -v -run TestSnapshotRestoreOverwritesCreateIndex -count=1 -timeout 60s ./agent/consul/state/` against the buggy build. The test creates catalog entries at raft index 10, snapshots, restores into a new store at raft index 100, and checks whether CreateIndex is preserved.

## Output

```
=== RUN   TestSnapshotRestoreOverwritesCreateIndex
    snapshot_index_bug_test.go:24: Original nodeA.CreateIndex = 10
    snapshot_index_bug_test.go:55: Restored nodeA.CreateIndex = 100 (original=10, restoreIdx=100)
    snapshot_index_bug_test.go:58: BUG: CreateIndex overwritten by restore index: got 100, want 10
--- FAIL: TestSnapshotRestoreOverwritesCreateIndex (0.00s)
FAIL
FAIL	github.com/hashicorp/consul/agent/consul/state	0.008s
FAIL
```
