# Verification: hashicorp/raft PR#581

## Test procedure

1. Build the test program that creates a 7-node cluster with concurrent writes and performs a targeted leadership transfer (see reproduce.md).

2. Run the test binary 30 times with a timeout:
   ```bash
   FAILURES=0
   TOTAL=30

   for i in $(seq 1 $TOTAL); do
       OUTPUT=$(timeout 60 ./raft-transfer-test 2>&1)
       if echo "$OUTPUT" | grep -q "TRANSFER_FAILED"; then
           FAILURES=$((FAILURES + 1))
           echo "Attempt $i: TRANSFER FAILED"
       else
           echo "Attempt $i: OK"
       fi
   done
   ```

3. Evaluate:
   ```bash
   if [ $FAILURES -gt 5 ]; then
       echo "FAIL: Bug is present — $FAILURES/$TOTAL transfers failed"
   else
       echo "PASS: Bug is fixed — transfers succeeded reliably"
   fi
   ```

## Verdict criteria
- **FAIL (bug present):** More than 5 out of 30 leadership transfers fail. The designated target does not become the new leader because concurrent writes on the old leader advance its log, causing the target to lose the election.
- **PASS (bug fixed):** 5 or fewer transfers fail out of 30. Leadership transfers succeed reliably even under concurrent write load.
- **Note:** Since this is a timing-sensitive race between writes and the transfer protocol, occasional failures (1-2 out of 30) may occur even with the fix due to other timing factors. The threshold of 5 distinguishes the systematic bug from rare transient failures.
