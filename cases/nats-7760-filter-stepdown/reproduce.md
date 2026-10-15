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

## Oracle verdict

`./bench.sh reproduce nats-7760-filter-stepdown` rebuilds the worktree and runs the oracle (`reproduce.sh`):

- **FAIL** (exit 1): on a 5-node cluster with an interest-based R5 stream, after the pull consumer's filters are edited from `orders.new`, `orders.paid` to `orders.new`, `orders.shipped` and its leader is stepped down, a message published to `orders.new` is not returned by a 5 s `nats consumer next`; it is also FAIL if the consumer delivers nothing even before the edit or a publish fails. A worktree that does not build, or a server that does not become healthy within 30 s, is also FAIL.
- **PASS** (exit 0): after the filter edit and the change of consumer leader, the consumer delivers the message published to `orders.new`.
- **ERROR** (exit 2): the trigger cannot be established (the stream or consumer cannot be created, the filter edit or step-down fails, or the consumer leader does not change), or the case is not set up (`REBUILD.sh`, the `nats-server` binary or the `nats` CLI is missing).
