# Verification: NATS Server #7760

```bash
#!/bin/bash
set -e

export NATS_URL=nats://127.0.0.1:4221

# Clean up from any previous runs
rm -rf /tmp/nats-test
for i in 1 2 3 4 5; do
cat > /tmp/n${i}.conf <<CONF
port: $((4220 + i))
server_name: n${i}
jetstream {
  store_dir: /tmp/nats-test/n${i}
  max_mem: 64MB
  max_file: 256MB
}
cluster {
  name: test-cluster
  listen: 0.0.0.0:$((6220 + i))
  routes: [
    nats-route://127.0.0.1:6221
    nats-route://127.0.0.1:6222
    nats-route://127.0.0.1:6223
    nats-route://127.0.0.1:6224
    nats-route://127.0.0.1:6225
  ]
}
CONF
done

for i in 1 2 3 4 5; do
  ./nats-server -c /tmp/n${i}.conf &
done
sleep 3

# Create stream and consumer
nats stream add TEST --subjects="events.>" --retention=interest --replicas=5 --storage=file --defaults
nats consumer add TEST myconsumer --filter="events.a" --ack=explicit --deliver=all --replay=instant --pull
sleep 1

# Edit filter
nats consumer edit TEST myconsumer --filter="events.b"
sleep 1

# Step down leader
nats stream cluster step-down TEST
sleep 3

# Publish
nats pub events.b "test-message"
sleep 1

# Try to consume
OUTPUT=$(nats consumer next TEST myconsumer --timeout=5s 2>&1 || true)

# Cleanup
pkill -f "nats-server.*nats-test" 2>/dev/null || true
rm -rf /tmp/nats-test /tmp/n*.conf

if echo "$OUTPUT" | grep -q "test-message"; then
    echo "PASS: Bug is fixed — consumer received message after step-down"
else
    echo "FAIL: Bug is present — consumer did not receive message after step-down"
fi
```

- **FAIL:** Consumer times out, no messages delivered after leader step-down.
- **PASS:** Consumer receives the published message normally.
