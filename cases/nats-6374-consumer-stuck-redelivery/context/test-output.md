# Test Output

Obtained by running `go test -v -run "TestJetStream.*Deliver|TestJetStream.*Redeliver" -timeout 120s ./server/` against the buggy build.

## Output

```
=== RUN   TestJetStreamClusterConsumerRedeliveredInfo
--- PASS: TestJetStreamClusterConsumerRedeliveredInfo (0.74s)
=== RUN   TestJetStreamClusterConsumerDeliveredSyncReporting
--- PASS: TestJetStreamClusterConsumerDeliveredSyncReporting (1.47s)
=== RUN   TestJetStreamClusterConsumerAckNoneInterestPolicyShouldNotRetainAfterDelivery
--- PASS: TestJetStreamClusterConsumerAckNoneInterestPolicyShouldNotRetainAfterDelivery (3.21s)
=== RUN   TestJetStreamClusterMaxDeliveriesOnInterestStreams
--- PASS: TestJetStreamClusterMaxDeliveriesOnInterestStreams (0.81s)
=== RUN   TestJetStreamClusterAckPendingWithMaxRedelivered
--- PASS: TestJetStreamClusterAckPendingWithMaxRedelivered (1.81s)
=== RUN   TestJetStreamClusterConsumerMaxDeliverUpdate
--- PASS: TestJetStreamClusterConsumerMaxDeliverUpdate (3.44s)
=== RUN   TestJetStreamClusterRedeliverBackoffs
--- PASS: TestJetStreamClusterRedeliverBackoffs (2.55s)
=== RUN   TestJetStreamClusterConsumerDeliverNewNotConsumingBeforeStepDownOrRestart
--- PASS: TestJetStreamClusterConsumerDeliverNewNotConsumingBeforeStepDownOrRestart (6.23s)
=== RUN   TestJetStreamClusterConsumerDeliverNewMaxRedeliveriesAndServerRestart
--- PASS: TestJetStreamClusterConsumerDeliverNewMaxRedeliveriesAndServerRestart (6.80s)
=== RUN   TestJetStreamClusterConsumerMaxDeliveryNumAckPendingBug
--- PASS: TestJetStreamClusterConsumerMaxDeliveryNumAckPendingBug (7.71s)
=== RUN   TestJetStreamClusterDoubleAckRedelivery
    jetstream_cluster_4_test.go:1656: Error: B:31482 nats: timeout
    jetstream_cluster_4_test.go:1656: Error: A:32929 nats: timeout
--- PASS: TestJetStreamClusterDoubleAckRedelivery (56.63s)
=== RUN   TestJetStreamConsumerBackoffNotRespectedWithMultipleInflightRedeliveries
--- PASS: TestJetStreamConsumerBackoffNotRespectedWithMultipleInflightRedeliveries (8.01s)
=== RUN   TestJetStreamConsumerBackoffWhenBackoffLengthIsEqualToMaxDeliverConfig
--- PASS: TestJetStreamConsumerBackoffWhenBackoffLengthIsEqualToMaxDeliverConfig (3.01s)
=== RUN   TestJetStreamSuperClusterConsumerDeliverNewBug
--- PASS: TestJetStreamSuperClusterConsumerDeliverNewBug (12.50s)
=== RUN   TestJetStreamConsumerMaxDeliveries
--- PASS: TestJetStreamConsumerMaxDeliveries (0.16s)
=== RUN   TestJetStreamBasicDeliverSubject
--- PASS: TestJetStreamBasicDeliverSubject (0.12s)
=== RUN   TestJetStreamAckAllRedelivery
--- PASS: TestJetStreamAckAllRedelivery (0.45s)
=== RUN   TestJetStreamWorkQueueAckWaitRedelivery
--- PASS: TestJetStreamWorkQueueAckWaitRedelivery (0.24s)
=== RUN   TestJetStreamWorkQueueNakRedelivery
--- PASS: TestJetStreamWorkQueueNakRedelivery (0.01s)
=== RUN   TestJetStreamWorkQueueTerminateDelivery
--- PASS: TestJetStreamWorkQueueTerminateDelivery (0.21s)
=== RUN   TestJetStreamConsumerMaxDeliveryAndServerRestart
--- PASS: TestJetStreamConsumerMaxDeliveryAndServerRestart (0.56s)
=== RUN   TestJetStreamRedeliveryAfterServerRestart
--- PASS: TestJetStreamRedeliveryAfterServerRestart (0.07s)
=== RUN   TestJetStreamActiveDelivery
--- PASS: TestJetStreamActiveDelivery (0.12s)
=== RUN   TestJetStreamRedeliverCount
--- PASS: TestJetStreamRedeliverCount (0.01s)
=== RUN   TestJetStreamRedeliverAndLateAck
--- PASS: TestJetStreamRedeliverAndLateAck (0.17s)
=== RUN   TestJetStreamStreamPurgeWithConsumerAndRedelivery
--- PASS: TestJetStreamStreamPurgeWithConsumerAndRedelivery (0.11s)
```
