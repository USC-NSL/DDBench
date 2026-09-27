# Test Output

Obtained by running `go test -v -run "TestJetStream.*Resource|TestJetStream.*Reset" -timeout 120s ./server/` against the buggy build.

## Output

```
=== RUN   TestJetStreamClusterStreamResetOnExpirationDuringPeerDownAndRestartWithLeaderChange
--- PASS: TestJetStreamClusterStreamResetOnExpirationDuringPeerDownAndRestartWithLeaderChange (3.64s)
=== RUN   TestJetStreamClusterStreamResetWithLargeFirstSeq
--- PASS: TestJetStreamClusterStreamResetWithLargeFirstSeq (2.87s)
=== RUN   TestJetStreamClusterStreamResetPreacks
--- PASS: TestJetStreamClusterStreamResetPreacks (3.81s)
=== RUN   TestJetStreamClusterStreamLastSequenceResetAfterStorageWipe
--- PASS: TestJetStreamClusterStreamLastSequenceResetAfterStorageWipe (10.29s)
=== RUN   TestJetStreamClusterStreamConsumerStateResetAfterRecreate
--- PASS: TestJetStreamClusterStreamConsumerStateResetAfterRecreate (7.02s)
=== RUN   TestJetStreamServerResourcesConfig
--- PASS: TestJetStreamServerResourcesConfig (0.00s)
PASS
ok  	github.com/nats-io/nats-server/v2/server	27.706s
```

Note: Existing tests pass. None of the reset tests verify that reserved resource counters are properly decremented after a non-delete reset cycle. The resource leak only manifests after multiple reset cycles accumulate.
