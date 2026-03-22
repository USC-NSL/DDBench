# Verification: hashicorp/raft #291

## Test

```bash
cd raft
go test -v -run TestVerifyLeaderOOM -timeout 120s
```

## Pass/fail criteria

- **FAIL (bug present):** Heap memory grows by more than 50MB during 10,000 VerifyLeader calls with a disconnected follower. The growth is proportional to the number of calls, indicating a leak.
- **PASS (bug fixed):** Heap memory growth is minimal (under 10MB) regardless of the number of VerifyLeader calls. Futures are properly cleaned up when they complete or fail.

## Additional manual check

Monitor the Go process memory with `pprof`:
```bash
go test -v -run TestVerifyLeaderOOM -memprofile mem.prof -timeout 120s
go tool pprof mem.prof
# In pprof: top, list verifyLeader
```

If the bug is present, `verifyLeader`-related allocations will dominate the heap profile.
