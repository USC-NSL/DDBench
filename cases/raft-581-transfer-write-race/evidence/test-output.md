# Test Output

Obtained by running `go test -v -run TestLeadershipTransferWritesDuringTransfer -count=1 -timeout 90s .` with a test that creates a 7-node cluster, applies concurrent writes during leadership transfers, and checks whether writes leak through during the transfer window, against the buggy build.

## Output

```
=== RUN   TestLeadershipTransferWritesDuringTransfer
    transfer_writes_bug_test.go:107: Transfer failures: 5/50
    transfer_writes_bug_test.go:119: Bug present: 5/50 leadership transfers failed — writes leaked through during transfer, causing the target to lose the election
--- FAIL: TestLeadershipTransferWritesDuringTransfer (40.81s)
FAIL
FAIL	github.com/hashicorp/raft	40.818s
```
