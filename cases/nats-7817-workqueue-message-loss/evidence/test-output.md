# Test Output

Obtained by running `go test -v -run TestJetStreamWQMaxDeliveryReached -count=1 -timeout 120s ./server/` against the buggy build.

## Output

```
=== RUN   TestJetStreamWQMaxDeliveryReached
    jetstream_test.go:22471: require no error, but got: no message found
--- FAIL: TestJetStreamWQMaxDeliveryReached (2.45s)
FAIL
FAIL	github.com/nats-io/nats-server/v2/server	2.463s
FAIL
```
