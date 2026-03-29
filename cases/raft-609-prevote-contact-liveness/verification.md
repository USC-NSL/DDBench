# Verification: hashicorp/raft #609

## Test procedure

1. Set up the raft source at the buggy commit (see setup.md).

2. Inject the test file into the raft source directory:
   ```bash
   cp inject_test.go prevote_contact_bug_test.go
   ```

3. Run the integration test multiple times:
   ```bash
   FAILURES=0
   TOTAL=3

   for i in $(seq 1 $TOTAL); do
       OUTPUT=$(INTEG_TESTS=1 timeout 120 go test -v -run "^TestPreVoteLeaderSpamBlocksElection$" -count=1 -timeout 90s . 2>&1)
       EXIT_CODE=$?
       if [ $EXIT_CODE -ne 0 ]; then
           FAILURES=$((FAILURES + 1))
           echo "Run $i: FAILED (no new leader elected)"
       else
           echo "Run $i: OK (new leader elected)"
       fi
   done
   ```

4. Evaluate:
   ```bash
   if [ $FAILURES -gt 0 ]; then
       echo "FAIL: Bug is present — pre-vote requests refresh last-contact, blocking elections"
   else
       echo "PASS: Bug is fixed — pre-vote requests do not block elections"
   fi
   ```

## Verdict criteria
- **FAIL (bug present):** One or more runs fail because no follower can become leader. The test detects that `WaitForAny(Leader, followers)` returns an error — no follower transitioned to candidate state because pre-vote requests kept refreshing `lastContact`.
- **PASS (bug fixed):** All runs succeed. Followers time out normally despite pre-vote spam and elect a new leader.
- **Note:** This bug is deterministic — on the buggy commit, pre-vote spam continuously refreshes `lastContact`, so followers never time out. The test should fail consistently on every run. Three iterations are used for confidence.
