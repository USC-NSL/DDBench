# Verification: NATS Server #7308

Run the Go test from the fix PR to verify:

```bash
cd nats-server

# Run the specific test added by PR #7348
go test -v -run "TestJetStreamClusterDeleteMsgEOF/R3" ./server/ -count=1 -timeout 120s 2>&1 | tail -20

if [ $? -eq 0 ]; then
    echo "PASS: Bug is fixed — deleting non-existent sequence returns error without cluster reset"
else
    echo "FAIL: Bug is present — deleting non-existent sequence triggers cluster state reset"
fi
```

## Verification criteria

- **FAIL (bug present):** The R3 subtest of `TestJetStreamClusterDeleteMsgEOF` fails. Deleting sequence 2 (beyond EOF) causes a cluster state reset, and the client receives a timeout instead of a proper error response. The test fails because `require_Error` expects a `JSStreamMsgDeleteFailedError` but the call hangs/times out.

- **PASS (bug fixed):** The test passes. Deleting a non-existent sequence beyond EOF returns a `JSStreamMsgDeleteFailedError(ErrStoreEOF)` immediately to the client without disrupting the cluster.
