# Verification: NATS #7718

## Automated test

```bash
#!/bin/bash
# Assumes NATS cluster is running with overlapping imports (see setup.md)

# Record initial subscription count
INITIAL=$(curl -s http://localhost:8222/varz | jq '.subscriptions')

# Create and destroy 200 ordered consumers
for i in $(seq 1 200); do
    timeout 2 nats -s nats://b:b@localhost:4222 consumer sub EVENTS \
      --ordered --count 1 2>/dev/null &
    sleep 0.1
done
wait

sleep 10

# Record final subscription count
FINAL=$(curl -s http://localhost:8222/varz | jq '.subscriptions')
LEAKED=$((FINAL - INITIAL))

echo "Initial: $INITIAL, Final: $FINAL, Leaked: $LEAKED"

if [ "$LEAKED" -gt "50" ]; then
    echo "FAIL: Bug is present — $LEAKED subscriptions leaked"
else
    echo "PASS: Bug is fixed — subscription count stable (delta: $LEAKED)"
fi
```

## Pass/fail criteria

- **FAIL (bug present):** Subscription count grows by 50+ after 200 consumer create/destroy cycles. The leaked subscriptions are never cleaned up.
- **PASS (bug fixed):** Subscription count remains stable (within a small delta of the initial count) after creating and destroying consumers. All subscriptions are properly cleaned up.
