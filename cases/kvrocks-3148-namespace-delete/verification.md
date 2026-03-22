# Verification: Kvrocks #3148

```bash
#!/bin/bash

rm -rf /tmp/kvrocks-test
mkdir -p /tmp/kvrocks-test/logs

./build/kvrocks --port 6666 --dir /tmp/kvrocks-test --log-dir /tmp/kvrocks-test/logs &
PID=$!
sleep 2

# Create two namespaces
redis-cli -p 6666 NAMESPACE ADD ns1 token1
redis-cli -p 6666 NAMESPACE ADD ns2 token2

# Try to set ns1's token to ns2's token
redis-cli -p 6666 NAMESPACE SET ns1 token2

# Check if ns2 still exists
RESULT=$(redis-cli -p 6666 NAMESPACE GET '*' 2>/dev/null)

kill $PID 2>/dev/null
rm -rf /tmp/kvrocks-test

if echo "$RESULT" | grep -q "ns2"; then
    echo "PASS: Bug is fixed — ns2 still exists after token collision"
else
    echo "FAIL: Bug is present — ns2 was deleted when ns1 took its token"
fi
```

- **FAIL:** `ns2` is missing from the namespace list.
- **PASS:** `ns2` still exists (either the SET was rejected or handled without deleting `ns2`).
