# Test Output

Obtained by running `go test -v -run "TestJetStream.*WQ|TestJetStream.*WorkQueue" -timeout 120s ./server/` against the buggy build.

## Output (selected, relevant tests)

```
=== RUN   TestJetStreamClusterWorkQueueLosingMessagesOnConsumerDelete
--- PASS: TestJetStreamClusterWorkQueueLosingMessagesOnConsumerDelete (6.51s)
=== RUN   TestJetStreamClusterWorkQueueConsumerReplicatedAfterScaleUp
--- PASS: TestJetStreamClusterWorkQueueConsumerReplicatedAfterScaleUp (2.41s)
=== RUN   TestJetStreamConsumerActionsOnWorkQueuePolicyStream
--- PASS: TestJetStreamConsumerActionsOnWorkQueuePolicyStream (0.04s)
=== RUN   TestJetStreamConsumerWorkQueuePolicyOverlap
--- PASS: TestJetStreamConsumerWorkQueuePolicyOverlap (0.03s)
=== RUN   TestJetStreamWorkQueueAckWaitRedelivery
--- PASS: TestJetStreamWorkQueueAckWaitRedelivery (0.24s)
=== RUN   TestJetStreamWorkQueueNakRedelivery
--- PASS: TestJetStreamWorkQueueNakRedelivery (0.01s)
=== RUN   TestJetStreamWorkQueueTerminateDelivery
--- PASS: TestJetStreamWorkQueueTerminateDelivery (0.21s)
PASS
```
