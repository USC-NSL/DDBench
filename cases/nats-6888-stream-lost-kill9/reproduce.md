# Reproduce: NATS #6888

## Prerequisites
A 3-node NATS JetStream cluster on v2.10.20 (see setup.md).

## Step 1: Create an R3 stream and publish data

```bash
nats -s nats://localhost:4222 stream add TESTSTREAM \
  --subjects "test.>" \
  --storage file \
  --replicas 3 \
  --retention limits \
  --max-msgs -1 \
  --max-bytes -1 \
  --discard old

# Publish some messages
for i in $(seq 1 1000); do
    nats -s nats://localhost:4222 pub "test.data" "message $i"
done
```

Verify the stream exists:
```bash
nats -s nats://localhost:4222 stream ls
# Should show TESTSTREAM
```

## Step 2: Ungraceful termination with kill -9

```bash
# Get PIDs of NATS server processes
PIDS=$(pgrep -f "nats-server")

# Kill one or two processes ungracefully
kill -9 $(echo $PIDS | awk '{print $1}')
sleep 2
kill -9 $(echo $PIDS | awk '{print $2}')
sleep 2
```

## Step 3: Restart killed nodes

```bash
./nats-server -c server1.conf &
sleep 2
./nats-server -c server2.conf &
sleep 5
```

## Step 4: Check stream status

```bash
nats -s nats://localhost:4222 stream ls
nats -s nats://localhost:4223 stream ls
nats -s nats://localhost:4224 stream ls
```

## Step 5: Repeat if needed

The bug may not trigger on every kill -9 cycle. Repeat steps 2-4 multiple times:

```bash
for attempt in $(seq 1 5); do
    echo "=== Attempt $attempt ==="

    # Kill all servers ungracefully
    pkill -9 -f nats-server
    sleep 2

    # Restart all
    ./nats-server -c server1.conf &
    ./nats-server -c server2.conf &
    ./nats-server -c server3.conf &
    sleep 5

    # Check streams
    STREAMS=$(nats -s nats://localhost:4222 stream ls 2>/dev/null | grep TESTSTREAM | wc -l)
    if [ "$STREAMS" -eq "0" ]; then
        echo "BUG TRIGGERED: Stream lost after kill -9 on attempt $attempt"
        break
    else
        echo "Stream still present"
    fi
done
```

## Expected result (bug present)
After one or more kill -9 + restart cycles, `nats stream ls` returns empty (no streams), even though stream data files still exist on disk in the store directories.
