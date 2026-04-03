# Test Output

Obtained by running `INTEG_TESTS=1 go test -v -run TestPreVoteLeaderSpamBlocksElection -count=1 -timeout 90s .` with a test that creates a 3-node TCP cluster, kills the leader, sends continuous pre-vote requests to followers, and checks whether a new leader can be elected, against the buggy build.

## Output

```
=== RUN   TestPreVoteLeaderSpamBlocksElection
    prevote_contact_bug_test.go:124: err: failed to find node in Leader state
--- FAIL: TestPreVoteLeaderSpamBlocksElection (2.27s)
FAIL
FAIL	github.com/hashicorp/raft	2.280s
```
