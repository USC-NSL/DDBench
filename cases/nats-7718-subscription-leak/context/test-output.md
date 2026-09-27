# Test Output

Obtained by running `go test -v -run "TestJetStream.*Import|TestJetStream.*Sub.*Leak" -timeout 120s ./server/` against the buggy build.

## Output

```
=== RUN   TestJetStreamSuperClusterImportConsumerStreamSubjectRemap
--- PASS: TestJetStreamSuperClusterImportConsumerStreamSubjectRemap (5.19s)
=== RUN   TestJetStreamSuperClusterConsumerAckSubjectWithStreamImportProtocolError
--- PASS: TestJetStreamSuperClusterConsumerAckSubjectWithStreamImportProtocolError (1.20s)
=== RUN   TestJetStreamAccountImportBasics
--- PASS: TestJetStreamAccountImportBasics (0.02s)
=== RUN   TestJetStreamAccountImportJSAdvisoriesAsService
--- PASS: TestJetStreamAccountImportJSAdvisoriesAsService (0.01s)
=== RUN   TestJetStreamAccountImportJSAdvisoriesAsStream
--- PASS: TestJetStreamAccountImportJSAdvisoriesAsStream (0.01s)
=== RUN   TestJetStreamAccountImportAll
--- PASS: TestJetStreamAccountImportAll (0.01s)
=== RUN   TestJetStreamImportReload
--- PASS: TestJetStreamImportReload (0.01s)
=== RUN   TestJetStreamImportConsumerStreamSubjectRemapSingle
--- PASS: TestJetStreamImportConsumerStreamSubjectRemapSingle (0.02s)
PASS
ok  	github.com/nats-io/nats-server/v2/server	13.173s
```

Note: Existing import-related tests pass. None of them set up overlapping stream imports with rapid consumer lifecycle churn and then verify subscription counts. The leak is cumulative — each consumer create/destroy cycle leaks route map entries, but this is only observable over many cycles via monitoring endpoints.
