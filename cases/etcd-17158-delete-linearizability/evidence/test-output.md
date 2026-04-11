# Test Output

Obtained by running `cd server && go test -v -timeout 60s ./storage/backend/` against the buggy build.

## Output

```
=== RUN   Test_bucketBuffer_CopyUsed_After_Add
--- PASS: Test_bucketBuffer_CopyUsed_After_Add (0.00s)
=== RUN   Test_bucketBuffer_CopyUsed
=== RUN   Test_bucketBuffer_CopyUsed/used_is_0
=== RUN   Test_bucketBuffer_CopyUsed/used_is_greater_than_0_and_less_than_len(buf)
=== RUN   Test_bucketBuffer_CopyUsed/used_is_equal_to_len(buf)
=== RUN   Test_bucketBuffer_CopyUsed/used_is_greater_than_len(buf)
--- PASS: Test_bucketBuffer_CopyUsed (0.00s)
=== RUN   TestBackendClose
--- PASS: TestBackendClose (0.05s)
=== RUN   TestBackendSnapshot
--- PASS: TestBackendSnapshot (0.00s)
=== RUN   TestBackendBatchIntervalCommit
--- PASS: TestBackendBatchIntervalCommit (0.10s)
=== RUN   TestBackendDefrag
--- PASS: TestBackendDefrag (0.10s)
=== RUN   TestBackendWriteback
--- PASS: TestBackendWriteback (0.00s)
=== RUN   TestConcurrentReadTx
--- PASS: TestConcurrentReadTx (0.00s)
=== RUN   TestBackendWritebackForEach
--- PASS: TestBackendWritebackForEach (0.00s)
=== RUN   TestBatchTxPut
--- PASS: TestBatchTxPut (0.00s)
=== RUN   TestBatchTxRange
--- PASS: TestBatchTxRange (0.00s)
=== RUN   TestBatchTxDelete
--- PASS: TestBatchTxDelete (0.00s)
=== RUN   TestBatchTxCommit
--- PASS: TestBatchTxCommit (0.00s)
=== RUN   TestBatchTxBatchLimitCommit
--- PASS: TestBatchTxBatchLimitCommit (0.00s)
=== RUN   TestBackendPreCommitHook
--- PASS: TestBackendPreCommitHook (0.00s)
=== RUN   TestBackendAutoCommitLimitHook
--- PASS: TestBackendAutoCommitLimitHook (0.00s)
=== RUN   TestBackendAutoCommitBatchIntervalHook
--- PASS: TestBackendAutoCommitBatchIntervalHook (1.04s)
=== RUN   TestLockVerify
=== RUN   TestLockVerify/call_lockInsideApply_from_inside_apply
=== RUN   TestLockVerify/call_lockInsideApply_from_outside_apply_(without_txPostLockInsideApplyHook)
=== RUN   TestLockVerify/call_lockInsideApply_from_outside_apply_(with_txPostLockInsideApplyHook)
=== RUN   TestLockVerify/call_lockOutsideApply_from_outside_apply
=== RUN   TestLockVerify/call_lockOutsideApply_from_inside_apply
=== RUN   TestLockVerify/call_Lock_from_unit_test
--- PASS: TestLockVerify (0.01s)
PASS
ok  	go.etcd.io/etcd/server/v3/storage/backend	1.348s
```

All existing backend tests pass. No test covers the interaction between `UnsafeDelete` and the buffered read path — the `TestBatchTxDelete` test only verifies that deletes succeed, not that the read buffer reflects them.
