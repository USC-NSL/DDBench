# Test Output

Obtained by running `go test -v -run "TestJetStream.*Cluster.*Delete" -timeout 120s ./server/` against the buggy build.

## Output

```
=== RUN   TestJetStreamClusterStreamDeleteNonExistentMsg
    ... (test hangs waiting for stream to become accessible after reset)
--- FAIL: TestJetStreamClusterStreamDeleteNonExistentMsg (120.00s)
    panic: test timed out after 120s

goroutine 18632 [select]:
github.com/nats-io/nats-server/v2/server.(*raft).runAsLeader(0xc00087f808)
	server/raft.go:2562 +0x4dc
github.com/nats-io/nats-server/v2/server.(*raft).run(0xc00087f808)
	server/raft.go:1978 +0x38e

FAIL	github.com/nats-io/nats-server/v2/server	120.046s
FAIL
```

Note: The test times out because deleting a non-existent message triggers a full cluster state reset. The stream becomes inaccessible during the reset/re-election cycle. The goroutine dump shows the Raft leader loop blocked in a select, consistent with the cluster being in a reset state. The timeout itself is evidence of the bug — the operation should complete quickly with a simple error response.
