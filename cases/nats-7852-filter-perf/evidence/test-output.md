# Test Output

Obtained by running `go test -v -run TestJetStreamConsumerSingleFilterSubjectInFilterSubjects -count=1 -timeout 120s ./server/` against the buggy build.

## Output

```
=== RUN   TestJetStreamConsumerSingleFilterSubjectInFilterSubjects
    jetstream_consumer_test.go:11339: FilterSubjects:["foo"] and FilterSubject:"foo" should produce equivalent consumers, but filter initialization differs: scalar filters initialized=false, array filters initialized=true. Single-element FilterSubjects incorrectly activates the slow multi-filter path (LoadNextMsgMulti instead of LoadNextMsg), causing >20% performance degradation.
--- FAIL: TestJetStreamConsumerSingleFilterSubjectInFilterSubjects (0.01s)
FAIL
FAIL	github.com/nats-io/nats-server/v2/server	0.023s
FAIL
```
