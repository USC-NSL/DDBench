# Reproduce: NATS Server #7760

## Step 1: Start a 5-node NATS cluster

Create 5 config files (`n1.conf` through `n5.conf`):

```bash
for i in 1 2 3 4 5; do
cat > n${i}.conf <<CONF
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
```

Start all 5 servers:
```bash
rm -rf /tmp/nats-test
for i in 1 2 3 4 5; do
  ./nats-server -c n${i}.conf &
done
sleep 3
```

## Step 2: Create stream and consumer

```bash
export NATS_URL=nats://127.0.0.1:4221

# Create an interest-based R5 stream
nats stream add TEST \
  --subjects="events.>" \
  --retention=interest \
  --replicas=5 \
  --storage=file \
  --defaults

# Create a consumer with filter subjects
nats consumer add TEST myconsumer \
  --filter="events.a" \
  --ack=explicit \
  --deliver=all \
  --replay=instant \
  --pull
```

## Step 3: Edit consumer filters

```bash
# Update the consumer to have different/additional filter subjects
nats consumer edit TEST myconsumer \
  --filter="events.b"
```

## Step 4: Step down the stream leader

```bash
nats stream cluster step-down TEST
sleep 2
```

## Step 5: Publish and try to consume

```bash
# Publish messages matching the updated filter
nats pub events.b "test message 1"
nats pub events.b "test message 2"

# Try to consume — this will timeout on the buggy version
nats consumer next TEST myconsumer --timeout=5s
```

## Expected result (bug present)
The `nats consumer next` command times out. No messages are delivered despite matching the filter subjects.
