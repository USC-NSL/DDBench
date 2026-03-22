# Verification: hashicorp/raft #212

## Test

```bash
cd raft
go test -v -run TestSnapshotInstallLoop -timeout 120s
```

## Pass/fail criteria

- **FAIL (bug present):** The test times out after 120 seconds, or the follower's `LastIndex()` is significantly behind the leader. Logs show repeated `"Failed to install snapshot"` messages in a loop.
- **PASS (bug fixed):** The follower successfully receives the snapshot and catches up to the leader within 30 seconds. The test passes and logs show `"PASS: Follower caught up"`.

## Manual verification

If running a live cluster, check:
```bash
# Follower should catch up within a reasonable time
# Compare leader and follower last applied index
# If follower is stuck and logs show repeated snapshot install attempts, bug is present
```
