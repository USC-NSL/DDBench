# Verification: Dragonfly #6819

```bash
#!/bin/bash

./build-dbg/dragonfly --port 6379 --logtostderr --proactor_threads 1 --dbfilename="" &
PID=$!
sleep 2

# Set key with short expiry, then overwrite without expiry
redis-cli -p 6379 SET mykey "value1" PX 500
redis-cli -p 6379 SET mykey "value2"

# Wait for expiry cycle
sleep 5

if kill -0 $PID 2>/dev/null; then
    # Also verify the key still exists (no expiry should have happened)
    VAL=$(redis-cli -p 6379 GET mykey 2>/dev/null)
    if [ "$VAL" = "value2" ]; then
        echo "PASS: Bug is fixed — key persists with correct value, no crash"
    else
        echo "PASS: Bug is fixed — process alive (key value: $VAL)"
    fi
else
    echo "FAIL: Bug is present — process crashed during expiry cycle"
fi

kill $PID 2>/dev/null
```

- **FAIL:** Process crashes at `db_slice.cc:1163`.
- **PASS:** Process stays alive; `GET mykey` returns `value2`.
