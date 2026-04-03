# Test Output

Obtained by running `go test -v -run TestJetStreamConsumerSwitchLeaderDuringInflightAck -count=1 -timeout 120s ./server/` and `go test -v -run TestJetStreamConsumerMessageDeletedDuringRedelivery -count=1 -timeout 120s ./server/` against the buggy build.

## Output

### Test 1: Leader step-down with inflight ack

```
=== RUN   TestJetStreamConsumerSwitchLeaderDuringInflightAck
    jetstream_consumer_test.go:2627: require no error, but got: nats: timeout
--- FAIL: TestJetStreamConsumerSwitchLeaderDuringInflightAck (5.18s)
FAIL
FAIL	github.com/nats-io/nats-server/v2/server	5.190s
FAIL
```

### Test 2: Deleted message during redelivery

```
=== RUN   TestJetStreamConsumerMessageDeletedDuringRedelivery
=== RUN   TestJetStreamConsumerMessageDeletedDuringRedelivery/Memory
    jetstream_consumer_test.go:2687: Expected one of [stream store EOF], got 'no message found'
=== RUN   TestJetStreamConsumerMessageDeletedDuringRedelivery/File
    jetstream_consumer_test.go:2687: Expected one of [stream store EOF], got 'deleted message'
--- FAIL: TestJetStreamConsumerMessageDeletedDuringRedelivery (0.03s)
    --- FAIL: TestJetStreamConsumerMessageDeletedDuringRedelivery/Memory (0.01s)
    --- FAIL: TestJetStreamConsumerMessageDeletedDuringRedelivery/File (0.02s)
FAIL
FAIL	github.com/nats-io/nats-server/v2/server	0.037s
FAIL
```
