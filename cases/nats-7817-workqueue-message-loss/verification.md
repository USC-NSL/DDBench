# Verification: NATS Server #7817

Run the Go test from the fix PR to verify:

```bash
#!/bin/bash

cd nats-server

# Run the specific test added/fixed by PR #7845
go test -v -run TestJetStreamWorkQueueMaxDeliver ./server/ -count=1 -timeout 120s 2>&1 | tail -20

if [ $? -eq 0 ]; then
    echo "PASS: Bug is fixed — max delivered messages preserved in WorkQueue"
else
    echo "FAIL: Bug is present — messages lost with WorkQueue retention on max-deliver"
fi
```

Alternatively, manual verification:

```bash
#!/bin/bash
export NATS_URL=nats://127.0.0.1:4231

# After running the reproduce steps, check stream message count
MSG_COUNT=$(nats stream info WORK --json 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin)['state']['messages'])")

# Cleanup
pkill -f "nats-server.*nats-wq-test" 2>/dev/null || true
rm -rf /tmp/nats-wq-test /tmp/nats-wq-n*.conf

if [ "$MSG_COUNT" -ge 18 ]; then
    echo "PASS: Bug is fixed — $MSG_COUNT messages remain (expected ~20)"
else
    echo "FAIL: Bug is present — only $MSG_COUNT messages remain (expected ~20)"
fi
```

- **FAIL:** Significantly fewer than 20 messages remain in the stream.
- **PASS:** Approximately 20 unacknowledged messages remain.
