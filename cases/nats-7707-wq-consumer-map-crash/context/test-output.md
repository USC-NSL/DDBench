# Test Output

Obtained by running `go test -race -v -run "TestJetStream.*WorkQueue.*Consumer|TestJetStream.*Consumer.*WorkQueue" -count=3 -timeout 120s ./server/` against the buggy build.

## Output

```
=== RUN   TestJetStreamClusterWorkQueueLosingMessagesOnConsumerDelete
--- PASS: TestJetStreamClusterWorkQueueLosingMessagesOnConsumerDelete (7.15s)
=== RUN   TestJetStreamClusterWorkQueueConsumerReplicatedAfterScaleUp
--- PASS: TestJetStreamClusterWorkQueueConsumerReplicatedAfterScaleUp (2.41s)
=== RUN   TestJetStreamConsumerActionsOnWorkQueuePolicyStream
--- PASS: TestJetStreamConsumerActionsOnWorkQueuePolicyStream (0.04s)
=== RUN   TestJetStreamConsumerWorkQueuePolicyOverlap
--- PASS: TestJetStreamConsumerWorkQueuePolicyOverlap (0.03s)
=== RUN   TestJetStreamClusterWorkQueueLosingMessagesOnConsumerDelete
--- PASS: TestJetStreamClusterWorkQueueLosingMessagesOnConsumerDelete (6.51s)
=== RUN   TestJetStreamClusterWorkQueueConsumerReplicatedAfterScaleUp
--- PASS: TestJetStreamClusterWorkQueueConsumerReplicatedAfterScaleUp (1.62s)
=== RUN   TestJetStreamConsumerActionsOnWorkQueuePolicyStream
--- PASS: TestJetStreamConsumerActionsOnWorkQueuePolicyStream (0.03s)
=== RUN   TestJetStreamConsumerWorkQueuePolicyOverlap
--- PASS: TestJetStreamConsumerWorkQueuePolicyOverlap (0.04s)
=== RUN   TestJetStreamClusterWorkQueueLosingMessagesOnConsumerDelete
--- PASS: TestJetStreamClusterWorkQueueLosingMessagesOnConsumerDelete (5.98s)
=== RUN   TestJetStreamClusterWorkQueueConsumerReplicatedAfterScaleUp
--- PASS: TestJetStreamClusterWorkQueueConsumerReplicatedAfterScaleUp (1.04s)
=== RUN   TestJetStreamConsumerActionsOnWorkQueuePolicyStream
--- PASS: TestJetStreamConsumerActionsOnWorkQueuePolicyStream (0.03s)
=== RUN   TestJetStreamConsumerWorkQueuePolicyOverlap
--- PASS: TestJetStreamConsumerWorkQueuePolicyOverlap (0.04s)
PASS
ok  	github.com/nats-io/nats-server/v2/server	28.082s
```
