# Reproduce: NATS Server #7726

## Step 1: Start a single NATS server with JetStream

```bash
rm -rf /tmp/nats-mixed-test
./nats-server --port 4222 --jetstream --store_dir /tmp/nats-mixed-test &
sleep 2
```

## Step 2: Create stream and consumer with mixed filters

```bash
export NATS_URL=nats://127.0.0.1:4222

# Create stream
nats stream add EVENTS \
  --subjects="events.>" \
  --retention=limits \
  --storage=file \
  --replicas=1 \
  --defaults

# Create consumer with mixed wildcard and literal filter subjects
nats consumer add EVENTS mixed \
  --filter="events.specific" \
  --filter="events.*" \
  --ack=explicit \
  --deliver=all \
  --replay=instant \
  --pull
```

## Step 3: Publish to the literal subject

```bash
nats pub events.specific "hello from specific"
sleep 1
```

## Step 4: Try to consume

```bash
nats consumer next EVENTS mixed --timeout=5s
```

## Expected result (bug present)
The consumer times out and does not deliver the message published to `events.specific`, even though it matches both filter patterns.

## Expected result (fixed)
The message is delivered successfully.
