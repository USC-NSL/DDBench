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

Note: Existing tests pass even with -race and -count=3. The race condition requires multiple clients on separate connections performing rapid concurrent consumer create/update/delete operations on the same WorkQueue stream. The existing tests use sequential consumer operations or single connections, which serializes requests and avoids the race window. The bug is timing-dependent and requires specific concurrency patterns not covered by the test suite.
