# Verification: Kvrocks #2512

```bash
# After establishing replication with master2 and waiting for sync:
# Switch to master1 (forces full sync -> PrepareRestoreDB with 2s sleep)
redis-cli -p 12514 SLAVEOF 127.0.0.1 12512
sleep 0.5

# Switch to master2 during the PrepareRestoreDB sleep window
# This will hang if the deadlock is present
timeout 10 redis-cli -p 12514 SLAVEOF 127.0.0.1 12513
SLAVEOF_RC=$?

# Check if slave is responsive
PONG=$(timeout 5 redis-cli -p 12514 PING)

if [ "$SLAVEOF_RC" -eq 124 ] || [ "$PONG" != "PONG" ]; then
    echo "FAIL: Bug is present — slave deadlocked"
else
    echo "PASS: Bug is fixed — slave remains responsive"
fi
```

- **FAIL:** The second `SLAVEOF` command times out and/or `PING` gets no response, indicating the server is deadlocked. The worker thread holding `WorkExclusivityGuard` is stuck on `thread.join()` waiting for the replication thread, which needs the same exclusive lock.
- **PASS:** Both `SLAVEOF` commands complete and the slave responds to `PING`, indicating the mutex ordering issue is resolved (fix moves `is_loading_ = true` before acquiring the exclusive lock).

**Note:** The reproduce script instruments the source with a 2-second sleep in `PrepareRestoreDB` to widen the naturally narrow race window. Without instrumentation, the deadlock is theoretically possible but extremely difficult to trigger externally.
