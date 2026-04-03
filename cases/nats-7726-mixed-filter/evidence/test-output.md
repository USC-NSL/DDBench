# Test Output

Obtained by running `go test -v -run TestPWCDoesntHideLiteral -count=1 -timeout 120s ./server/gsl/` against the buggy build.

## Output

```
# github.com/nats-io/nats-server/v2/server/gsl [github.com/nats-io/nats-server/v2/server/gsl.test]
server/gsl/gsl_test.go:557:8: undefined: NewSublistWithCache
server/gsl/gsl_test.go:558:10: undefined: newSub
server/gsl/gsl_test.go:560:10: undefined: newSub
server/gsl/gsl_test.go:564:11: undefined: NewSubjectTree
FAIL	github.com/nats-io/nats-server/v2/server/gsl [build failed]
FAIL
```
