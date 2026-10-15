# Test Output

Obtained by running `go test -bench "BenchmarkJetStream" -benchtime 3s ./server/` against the buggy build.

## Output

```
$ go test -bench "BenchmarkJetStream" -benchtime 3s ./server/ 2>&1 | head -5
testing: warning: no benchmarks to run
PASS
ok  	github.com/nats-io/nats-server/v2/server	0.050s
```
