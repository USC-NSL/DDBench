# Verification: Kvrocks #3208

```bash
# Start master + replica, wait for sync
# Write a 16KB value to master → triggers high read threshold on replica
# Write a small value to master immediately after
# Poll replica for the small value with a 5-second deadline

FOUND=false
for i in $(seq 1 50); do
    VAL=$(redis-cli -p 13209 GET small_key 2>/dev/null)
    if [ "$VAL" = "small_value" ]; then
        FOUND=true
        break
    fi
    sleep 0.1
done

if [ "$FOUND" = "true" ]; then
    echo "PASS: Bug is fixed — small value replicated within timeout"
else
    echo "FAIL: Bug is present — small value not replicated (replication stalled)"
fi
```

- **FAIL:** The small value written to master does not appear on the replica within 5 seconds after a large batch, indicating the replication stream is stalled.
- **PASS:** The small value appears on the replica within 5 seconds, indicating the replication stream processes data promptly regardless of prior batch size.
