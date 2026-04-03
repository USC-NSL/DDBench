# Test Output

Obtained by running `go test -v -run TestCompactLogsNegativeRange -count=1 -timeout 30s .` with a spy LogStore that detects invalid `DeleteRange` calls against the buggy build.

## Output

```
=== RUN   TestCompactLogsNegativeRange
    negative_range_test.go:38: Log store range: 100 to 200
    negative_range_test.go:56: Calling compactLogs(50); log store first index is 100
    negative_range_test.go:61: FAIL: Bug is present — DeleteRange called with from=100 > to=50 (invalid negative range)
--- FAIL: TestCompactLogsNegativeRange (0.00s)
FAIL
FAIL	github.com/hashicorp/raft	0.004s
```
