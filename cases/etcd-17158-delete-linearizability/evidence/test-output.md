# Test Output

Obtained by running `cd server && go test -v -timeout 60s ./storage/backend/` against the buggy build.

## Output

```
=== RUN   TestBackendClose
--- PASS: TestBackendClose (0.00s)
=== RUN   TestBackendSnapshot
--- PASS: TestBackendSnapshot (0.01s)
=== RUN   TestBackendSnapshotCopy
--- PASS: TestBackendSnapshotCopy (0.00s)
=== RUN   TestBackendAutoCommitLimitHook
--- PASS: TestBackendAutoCommitLimitHook (0.00s)
=== RUN   TestBackendAutoCommitBatchIntervalHook
--- PASS: TestBackendAutoCommitBatchIntervalHook (1.03s)
=== RUN   TestLockVerify
--- PASS: TestLockVerify (0.01s)
PASS
ok  	go.etcd.io/etcd/server/v3/storage/backend	1.212s
```

All existing backend tests pass, indicating there is no test coverage for the interaction between `UnsafeDelete` and the buffered read path.
