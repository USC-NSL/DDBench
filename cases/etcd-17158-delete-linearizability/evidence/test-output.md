# Test Failure Output

Obtained by running `go test -v -run "^TestRangeAfterDeleteMatch$" -count=1 -timeout 60s ./storage/backend/` from the `server/` directory against the buggy build.

## Output

```
=== RUN   TestRangeAfterDeleteMatch
    delete_linearizability_bug_test.go:53: FAIL: BatchTx and ReadTx disagree after delete -- BatchTx keys: [], ReadTx keys: [foo]
    delete_linearizability_bug_test.go:58: FAIL: Bug is present -- deleted key still visible via ReadTx
--- FAIL: TestRangeAfterDeleteMatch (0.00s)
FAIL
FAIL	go.etcd.io/etcd/server/v3/storage/backend	0.018s
FAIL
```
