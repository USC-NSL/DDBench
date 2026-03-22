# Verification: Redpanda #25769

## Test procedure

1. Start Redpanda (see setup.md).

2. Create a topic:
   ```bash
   docker exec redpanda rpk topic create test-verify -p 1
   ```

3. Produce compressed records with known timestamps using a test program (see reproduce.md for the Go code). The key is:
   - Use gzip (or any) compression
   - Produce records with distinct, known timestamps
   - Record the expected offset-to-timestamp mapping

4. Call `ListOffsets` for a timestamp that falls in the middle of the produced records:
   ```go
   // Query for timestamp T2 (the timestamp of the 3rd record)
   offsets, _ := adminClient.ListOffsetsAfterMilli(ctx, T2.UnixMilli(), "test-verify")
   result := offsets.Lookup("test-verify", 0)
   fmt.Printf("ListOffsets returned offset: %d (expected: 2)\n", result.Offset)
   ```

5. Evaluate:
   ```bash
   # Compare returned offset with expected offset
   if [ "$RETURNED_OFFSET" -eq "$EXPECTED_OFFSET" ]; then
       echo "PASS: Bug is fixed — ListOffsets returns correct offset for compressed batch"
   else
       echo "FAIL: Bug is present — ListOffsets returned $RETURNED_OFFSET, expected $EXPECTED_OFFSET"
   fi
   ```

6. Additional validation — repeat with uncompressed records to confirm the test logic is correct:
   ```bash
   # Same test without compression should always pass (even on buggy versions)
   docker exec redpanda rpk topic create test-verify-uncompressed -p 1
   # Produce without compression, query ListOffsets — should return correct offset
   ```

7. Cleanup:
   ```bash
   docker exec redpanda rpk topic delete test-verify test-verify-uncompressed
   docker rm -f redpanda
   ```

## Verdict criteria
- **FAIL (bug present):** `ListOffsets` returns a different offset than the one corresponding to the queried timestamp for compressed batches, while returning correct results for uncompressed batches.
- **PASS (bug fixed):** `ListOffsets` returns the correct offset for both compressed and uncompressed batches.
