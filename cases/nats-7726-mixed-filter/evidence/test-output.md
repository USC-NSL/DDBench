# Test Output

Obtained by running `go test -v -run "TestSubject|TestFilter" -timeout 60s ./server/` against the buggy build.

## Output

```
=== RUN   TestSubjectRenameViaJetStreamAck
--- PASS: TestSubjectRenameViaJetStreamAck (0.00s)
=== RUN   TestSubjectTransformHelpers
--- PASS: TestSubjectTransformHelpers (0.00s)
=== RUN   TestSubjectTransforms
--- PASS: TestSubjectTransforms (0.00s)
=== RUN   TestSubjectTransformDoesntPanicTransformingMissingToken
--- PASS: TestSubjectTransformDoesntPanicTransformingMissingToken (0.00s)
=== RUN   TestSubjectIsLiteral
--- PASS: TestSubjectIsLiteral (0.00s)
=== RUN   TestSubjectToken
--- PASS: TestSubjectToken (0.00s)
PASS
ok  	github.com/nats-io/nats-server/v2/server	0.030s
```

Note: Existing tests pass but do not cover the specific scenario of mixed wildcard + literal filter subjects in a multi-filter consumer. The `intersectStree` function's early-return behavior is only triggered when a wildcard and a literal filter coexist at the same subject level, which is not tested.
