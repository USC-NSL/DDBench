# Verification: NATS #6888

## Automated test

```bash
#!/bin/bash
# Assumes cluster is running and TESTSTREAM was created (see reproduce.md)

PASS=true

for attempt in $(seq 1 10); do
    # Kill all servers ungracefully
    pkill -9 -f nats-server
    sleep 2

    # Restart all
    ./nats-server -c server1.conf &
    ./nats-server -c server2.conf &
    ./nats-server -c server3.conf &
    sleep 5

    # Check if stream still exists
    STREAM_COUNT=$(nats -s nats://localhost:4222 stream ls --json 2>/dev/null | jq '.streams | length' 2>/dev/null)

    if [ "$STREAM_COUNT" = "0" ] || [ -z "$STREAM_COUNT" ]; then
        echo "FAIL: Bug is present — stream lost after kill -9 on attempt $attempt"
        PASS=false
        break
    fi

    # Also verify data is accessible
    MSG_COUNT=$(nats -s nats://localhost:4222 stream info TESTSTREAM --json 2>/dev/null | jq '.state.messages' 2>/dev/null)
    if [ "$MSG_COUNT" = "0" ] || [ -z "$MSG_COUNT" ]; then
        echo "FAIL: Bug is present — stream exists but messages lost on attempt $attempt"
        PASS=false
        break
    fi

    echo "Attempt $attempt: Stream OK (${MSG_COUNT} messages)"
done

if $PASS; then
    echo "PASS: Bug is fixed — stream survived all kill -9 cycles"
fi
```

## Pass/fail criteria

- **FAIL (bug present):** After kill -9 and restart, `nats stream ls` returns empty or the stream's message count is 0. The Raft meta-stream has lost track of the JetStream stream.
- **PASS (bug fixed):** The stream survives all kill -9 + restart cycles. Stream listing shows the stream, and messages are accessible.
