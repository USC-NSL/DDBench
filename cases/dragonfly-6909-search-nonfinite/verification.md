# Verification: Dragonfly #6909

```bash
#!/bin/bash

./build-dbg/dragonfly --port 6379 --logtostderr --proactor_threads 1 --dbfilename="" &
PID=$!
sleep 2

# Create search index with NUMERIC field
redis-cli -p 6379 FT.CREATE myidx ON HASH PREFIX 1 doc: SCHEMA score NUMERIC
sleep 1

# Insert document with non-finite value
redis-cli -p 6379 HSET doc:1 score inf
sleep 1

# Try to search
redis-cli -p 6379 FT.SEARCH myidx "*" 2>/dev/null

sleep 1
if kill -0 $PID 2>/dev/null; then
    echo "PASS: Bug is fixed — process survived non-finite numeric value"
else
    echo "FAIL: Bug is present — process crashed"
fi

kill $PID 2>/dev/null
```

- **FAIL:** Process crashes (SIGABRT or SIGSEGV).
- **PASS:** Process stays alive; search returns result or error without crashing.
