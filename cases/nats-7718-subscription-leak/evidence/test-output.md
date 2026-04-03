# Test Output

Obtained by running `go test -v -run "TestJetStreamClusterLeakedSubsWithStreamImportOverlappingJetStreamSubs" -count=1 -timeout 120s ./server/` against the buggy build.

## Output

```
=== RUN   TestJetStreamClusterLeakedSubsWithStreamImportOverlappingJetStreamSubs
    jetstream_cluster_3_test.go:6793: expected 213 subs, got 214
--- FAIL: TestJetStreamClusterLeakedSubsWithStreamImportOverlappingJetStreamSubs (3.33s)
FAIL
FAIL	github.com/nats-io/nats-server/v2/server	3.340s
FAIL
```
