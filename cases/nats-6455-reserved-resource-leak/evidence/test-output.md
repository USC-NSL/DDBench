# Test Output

Obtained by running `go test -v -run "^TestJetStreamClusterReservedResourcesAccountingAfterClusterReset$" -count=1 -timeout 120s ./server/` against the buggy build.

## Output

```
=== RUN   TestJetStreamClusterReservedResourcesAccountingAfterClusterReset
=== RUN   TestJetStreamClusterReservedResourcesAccountingAfterClusterReset/last_sequence_mismatch
    reserved_resource_leak_test.go:74: require int64 equal, but got: 2147483648 != 1073741824
=== RUN   TestJetStreamClusterReservedResourcesAccountingAfterClusterReset/first_sequence_mismatch
--- FAIL: TestJetStreamClusterReservedResourcesAccountingAfterClusterReset (4.36s)
    --- FAIL: TestJetStreamClusterReservedResourcesAccountingAfterClusterReset/last_sequence_mismatch (3.15s)
    --- PASS: TestJetStreamClusterReservedResourcesAccountingAfterClusterReset/first_sequence_mismatch (1.21s)
FAIL
FAIL	github.com/nats-io/nats-server/v2/server	4.373s
FAIL
```
