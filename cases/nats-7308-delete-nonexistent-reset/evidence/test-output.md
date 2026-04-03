# Test Output

Obtained by running `go test -v -run "TestJetStreamClusterDeleteMsgEOF" -count=1 -timeout 120s ./server/` against the buggy build.

## Output

```
=== RUN   TestJetStreamClusterDeleteMsgEOF
=== RUN   TestJetStreamClusterDeleteMsgEOF/R1
=== RUN   TestJetStreamClusterDeleteMsgEOF/R3
    jetstream_cluster_1_test.go:9004: Expected one of [stream store EOF (10057)], got 'context deadline exceeded'
--- FAIL: TestJetStreamClusterDeleteMsgEOF (12.52s)
    --- PASS: TestJetStreamClusterDeleteMsgEOF/R1 (0.46s)
    --- FAIL: TestJetStreamClusterDeleteMsgEOF/R3 (12.06s)
FAIL
FAIL	github.com/nats-io/nats-server/v2/server	12.536s
FAIL
```
