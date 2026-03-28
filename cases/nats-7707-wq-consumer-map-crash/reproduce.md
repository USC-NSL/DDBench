# Reproduce: NATS #7707

## Prerequisites
A single NATS server with JetStream enabled (see setup.md).

## Step 1: Create a WorkQueue stream

```bash
nats stream add WQ_RACE \
  --subjects "wq.>" \
  --storage memory \
  --retention work \
  --max-msgs -1 \
  --max-bytes -1 \
  --discard old
```

## Step 2: Publish messages continuously

In one terminal, publish messages with varying subjects:

```bash
while true; do
    for i in $(seq 0 7); do
        nats pub "wq.partition.$i" "payload" &
    done
    wait
done
```

## Step 3: Rapidly create and delete consumers

In another terminal, rapidly create and delete consumers with unique filter subjects:

```bash
for round in $(seq 1 100); do
    for i in $(seq 0 7); do
        nats consumer add WQ_RACE "C_$i" \
          --filter "wq.partition.$i" \
          --ack explicit \
          --deliver all \
          --max-deliver 1 2>/dev/null &
    done
    wait
    for i in $(seq 0 7); do
        nats consumer rm WQ_RACE "C_$i" -f 2>/dev/null &
    done
    wait
done
```

## Step 4: Check server status

Monitor the server process. Under the buggy version, the server will crash with:

```
fatal error: concurrent map iteration and map write
```

## Automated reproduction (Go test)

The `reproduce.sh` script injects a Go test that creates a WorkQueue stream and spawns multiple goroutines that concurrently create/update/delete consumers while messages are being published. The test is run with the Go race detector (`-race` flag) up to 5 times.

## Expected result (bug present)

The Go race detector reports a `DATA RACE` or the server crashes with `fatal error: concurrent map iteration and map write`. The crash originates from iterating a map while another goroutine modifies it during consumer partition uniqueness checks.
