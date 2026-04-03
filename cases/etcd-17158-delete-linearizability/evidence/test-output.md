# Test Assertion Output: etcd-17158-delete-linearizability

## How this was obtained

Ran the injected regression test via `bench.sh reproduce`:

```bash
./bench.sh reproduce etcd-17158-delete-linearizability
```

Which executes inside the container:

```bash
cd /workspace/worktrees/etcd-17158-delete-linearizability/server
go test -v -run "^TestRangeAfterDeleteMatch$" -count=1 -timeout 60s ./storage/backend/
```

## Evidence

```
=== RUN   TestRangeAfterDeleteMatch
    delete_linearizability_bug_test.go:83: FAIL: BatchTx and ReadTx disagree after delete
          BatchTx keys: [] (correct)
          ReadTx keys:  [foo] (stale -- delete not reflected in read buffer)
        This is the linearizability violation described in etcd#17158:
          UnsafeDelete bypasses the read buffer, so a read after delete
          returns the deleted key from the stale buffer.
    delete_linearizability_bug_test.go:110: FAIL: ForEach inconsistency after delete
          BatchTx ForEach keys: []
          ReadTx ForEach keys:  [foo]
    delete_linearizability_bug_test.go:117: FAIL: Bug is present -- deleted key still visible via ReadTx, violating linearizability (etcd#17158)
--- FAIL: TestRangeAfterDeleteMatch (0.00s)
FAIL
FAIL	go.etcd.io/etcd/server/v3/storage/backend	0.012s
FAIL
```

## What this tells a developer

After deleting a key, the write transaction path (`BatchTx`) correctly shows the key as gone, but the read transaction path (`ReadTx`) still returns the deleted key. Both `UnsafeRange` and `ForEach` show the same inconsistency. This suggests the delete operation is not propagating to whatever state the read path consults, even though puts work correctly through both paths. Investigating how deletes and puts differ in their interaction with the storage backend's buffering layer would be a productive starting point.
