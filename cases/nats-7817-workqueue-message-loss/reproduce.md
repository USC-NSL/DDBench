# Reproduce: NATS Server #7817

## Step 1: Start a 3-node NATS cluster

```bash
for i in 1 2 3; do
cat > /tmp/nats-wq-n${i}.conf <<CONF
port: $((4230 + i))
server_name: wq-n${i}
jetstream {
  store_dir: /tmp/nats-wq-test/n${i}
  max_mem: 64MB
  max_file: 256MB
}
cluster {
  name: wq-cluster
  listen: 0.0.0.0:$((6230 + i))
  routes: [
    nats-route://127.0.0.1:6231
    nats-route://127.0.0.1:6232
    nats-route://127.0.0.1:6233
  ]
}
CONF
done

rm -rf /tmp/nats-wq-test
for i in 1 2 3; do
  ./nats-server -c /tmp/nats-wq-n${i}.conf &
done
sleep 3
```

## Step 2: Create WorkQueue stream with R3

```bash
export NATS_URL=nats://127.0.0.1:4231

nats stream add WORK \
  --subjects="work.>" \
  --retention=work \
  --replicas=3 \
  --storage=file \
  --discard=old \
  --max-msgs=-1 \
  --max-bytes=-1 \
  --max-age=-1 \
  --defaults
```

## Step 3: Create consumer with max-deliver

```bash
nats consumer add WORK worker \
  --ack=explicit \
  --deliver=all \
  --replay=instant \
  --max-deliver=3 \
  --pull \
  --defaults
```

## Step 4: Publish 200 messages

```bash
for i in $(seq 1 200); do
  nats pub work.task "message-$i"
done
sleep 1
```

## Step 5: Consume, skip every 10th message

```bash
# Consume messages, ACK all except every 10th
for i in $(seq 1 200); do
  MSG=$(nats consumer next WORK worker --timeout=5s --raw 2>/dev/null)
  if [ $? -ne 0 ]; then break; fi
  if [ $((i % 10)) -ne 0 ]; then
    # ACK this message (the next command auto-acks in normal mode)
    true
  fi
done
```

Note: The exact consumer interaction depends on your nats CLI version. The key is to consume all 200 messages but leave every 10th unacknowledged so they hit max-deliver.

## Step 6: Check stream state

```bash
nats stream info WORK --json | python3 -c "import json,sys; d=json.load(sys.stdin); print(f\"Messages in stream: {d['state']['messages']}\")"
```

## Expected result (bug present)
The stream shows significantly fewer than 20 messages remaining (e.g., 9 or fewer). Messages that reached max-deliver were incorrectly removed.
