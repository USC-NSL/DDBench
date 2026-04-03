# Test Output

Obtained by running `go test -v -run TestNamespaceReplicateWithFullSync -count=1 -timeout 120s ./tests/gocase/unit/namespace/` against the buggy build.

## Output

```
=== RUN   TestNamespaceReplicateWithFullSync
    namespace_fullsync_bug_test.go:49: 
        	Error Trace:	/workspace/worktrees/kvrocks-2520-namespace-fullsync/tests/gocase/unit/namespace/namespace_fullsync_bug_test.go:49
        	Error:      	Received unexpected error:
        	            	redis: nil
        	Test:       	TestNamespaceReplicateWithFullSync
--- FAIL: TestNamespaceReplicateWithFullSync (3.42s)
FAIL
FAIL	github.com/apache/kvrocks/tests/gocase/unit/namespace	3.430s
FAIL
```
