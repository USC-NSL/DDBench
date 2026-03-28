# Verification: hashicorp/raft #517

## Test procedure

1. Set up the test program (see reproduce.md).

2. Build with the Go race detector:
   ```bash
   go build -race -o raft-race-test .
   ```

3. Run the test multiple times with a timeout:
   ```bash
   RACES=0
   TOTAL=30

   for i in $(seq 1 $TOTAL); do
       OUTPUT=$(timeout 60 ./raft-race-test 2>&1)
       if echo "$OUTPUT" | grep -q "WARNING: DATA RACE"; then
           RACES=$((RACES + 1))
           echo "Attempt $i: DATA RACE DETECTED"
       else
           echo "Attempt $i: OK"
       fi
   done
   ```

4. Evaluate:
   ```bash
   if [ $RACES -gt 0 ]; then
       echo "FAIL: Bug is present — $RACES/$TOTAL runs triggered a data race"
   else
       echo "PASS: Bug is fixed — all $TOTAL runs completed without data race"
   fi
   ```

## Verdict criteria
- **FAIL (bug present):** One or more runs out of 30 trigger the Go race detector (`WARNING: DATA RACE` found in stderr).
- **PASS (bug fixed):** All 30 runs complete without any race detector warnings.
- **Note:** Since this is a race condition, a single successful run is not conclusive. Run at least 30 iterations. The race occurs during leadership transfer between the candidate goroutine and the append entries handler, so the test must trigger multiple leadership transfers to reliably reproduce the race.
