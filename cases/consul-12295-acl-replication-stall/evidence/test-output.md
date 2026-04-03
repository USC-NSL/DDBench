# Test Output

Obtained by running `go test -v -run "^TestManager_IsRunningAfterParentContextCancel$" -count=1 -timeout 60s ./lib/routine/` against the buggy build.

## Output

```
=== RUN   TestManager_IsRunningAfterParentContextCancel
=== PAUSE TestManager_IsRunningAfterParentContextCancel
=== CONT  TestManager_IsRunningAfterParentContextCancel
    inject_test.go:71: 
        	Error Trace:	inject_test.go:71
        	Error:      	Should be false
        	Test:       	TestManager_IsRunningAfterParentContextCancel
        	Messages:   	IsRunning returned true after parent context was cancelled while goroutine is still blocking on a long-running call. This causes startACLReplication() to skip restarting the routine after leadership re-election, leaving the secondary datacenter with permanently stale ACL state.
2026-04-03T12:29:01.712Z [INFO]  TestManager_IsRunningAfterParentContextCancel: started routine: routine=acl-policy-replication
--- FAIL: TestManager_IsRunningAfterParentContextCancel (0.00s)
FAIL
FAIL	github.com/hashicorp/consul/lib/routine	0.004s
FAIL
```
