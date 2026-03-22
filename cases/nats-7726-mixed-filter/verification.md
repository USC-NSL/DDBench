# Verification: NATS Server #7726

```bash
#!/bin/bash

rm -rf /tmp/nats-mixed-test
./nats-server --port 4222 --jetstream --store_dir /tmp/nats-mixed-test &
PID=$!
sleep 2

export NATS_URL=nats://127.0.0.1:4222

# Create stream and consumer with mixed filters
nats stream add EVENTS --subjects="events.>" --retention=limits --storage=file --replicas=1 --defaults
nats consumer add EVENTS mixed --filter="events.specific" --filter="events.*" --ack=explicit --deliver=all --replay=instant --pull
sleep 1

# Publish to literal subject
nats pub events.specific "test-mixed-filter"
sleep 1

# Try to consume
OUTPUT=$(nats consumer next EVENTS mixed --timeout=5s 2>&1 || true)

kill $PID 2>/dev/null
rm -rf /tmp/nats-mixed-test

if echo "$OUTPUT" | grep -q "test-mixed-filter"; then
    echo "PASS: Bug is fixed — consumer received message on literal subject"
else
    echo "FAIL: Bug is present — consumer did not receive message on literal subject"
fi
```

- **FAIL:** Consumer times out; literal subject messages not delivered.
- **PASS:** Consumer receives the message published to `events.specific`.
