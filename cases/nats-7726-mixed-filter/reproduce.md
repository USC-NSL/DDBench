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

## Oracle verdict

`./bench.sh reproduce nats-7726-mixed-filter` rebuilds the worktree and runs the oracle (`reproduce.sh`):

- **FAIL** (exit 1): with file or memory storage, a pull consumer whose filter subjects mix two partial-wildcard patterns with the literal `events.main.datastore.result.created` does not deliver the message published to that literal subject (after 7 non-matching `events.main.datastore.*` messages) within a 3 s fetch, or delivers a different message. A worktree that does not build, or an oracle test that does not compile or is skipped, is also FAIL.
- **PASS** (exit 0): for both storage types the fetch returns the message on `events.main.datastore.result.created` with its original payload.
- **ERROR** (exit 2): the case is not set up (`REBUILD.sh` or the `nats-server` binary is missing), or Go module downloads fail so the oracle test cannot run.
