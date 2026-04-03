# Test Output

Obtained by running `make ct CT_SUITES=ra_server CT_OPTS="-case candidate_receives_pre_vote"` against the buggy build.

## Output

```
Common Test v1.26.2.4 starting (cwd is /workspace/worktrees/ra-439-election-livelock)

TEST INFO: 1 test(s), 1 case(s) in 1 suite(s)

Testing worktrees.ra-439-election-livelock.ra_server_SUITE.candidate_receives_pre_vote: Starting test, 1 test cases

- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
ra_server_SUITE:candidate_receives_pre_vote failed on line 1940
Reason: {badmatch,{candidate,#{log =>
                 {state,3,
   ...}
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

Testing worktrees.ra-439-election-livelock.ra_server_SUITE.candidate_receives_pre_vote: *** FAILED test case 1 of 1 ***
Testing worktrees.ra-439-election-livelock.ra_server_SUITE.candidate_receives_pre_vote: TEST COMPLETE, 0 ok, 1 failed of 1 test cases
```
