# Verification: Consul #12295

```bash
go test -v -run '^TestManager_IsRunningAfterParentContextCancel$' \
    -count=1 -timeout 60s ./lib/routine/
```

- **FAIL:** Test fails with `"IsRunning returned true after parent context was cancelled"` — the routine lifecycle tracker does not detect parent-context cancellation, so `IsRunning()` returns `true` while the goroutine is blocking. `startACLReplication()` sees a running routine and returns early without restarting replication. Exit code 1.
- **PASS:** Test passes — `IsRunning()` correctly returns `false` after the parent context is cancelled, regardless of the goroutine's blocking state. `startACLReplication()` proceeds to restart the replication routines. Exit code 0.
