# Verification: hashicorp/raft #268

## Test procedure

1. Set up the test program (see reproduce.md).

2. Run the test multiple times with a timeout:
   ```bash
   FAILURES=0
   TOTAL=20

   for i in $(seq 1 $TOTAL); do
       timeout 35 go run main.go > /dev/null 2>&1
       EXIT_CODE=$?
       if [ $EXIT_CODE -ne 0 ]; then
           FAILURES=$((FAILURES + 1))
           echo "Attempt $i: DEADLOCK (exit code $EXIT_CODE)"
       else
           echo "Attempt $i: OK"
       fi
   done
   ```

3. Evaluate:
   ```bash
   if [ $FAILURES -gt 0 ]; then
       echo "FAIL: Bug is present — $FAILURES/$TOTAL runs deadlocked"
   else
       echo "PASS: Bug is fixed — all $TOTAL runs completed without deadlock"
   fi
   ```

4. Alternative: Use Go test with race detector and deadlock detection:
   ```go
   func TestShutdownDuringSnapshot(t *testing.T) {
       for i := 0; i < 50; i++ {
           // Set up raft node, apply entries, call Shutdown()
           // with a deadline context
           // If context deadline exceeded, the test fails
       }
   }
   ```

## Verdict criteria
- **FAIL (bug present):** One or more runs out of 20 hang for > 30 seconds (deadlock in `Shutdown()`).
- **PASS (bug fixed):** All 20 runs complete `Shutdown()` within a few seconds.
- **Note:** Since this is a race condition, a single successful run is not conclusive. Run at least 20 iterations. Adjust `SnapshotInterval` and `SnapshotThreshold` to increase the likelihood of the race.
