# Verification: Dragonfly #6907

```bash
./build-dbg/dragonfly --port 6379 --logtostderr --proactor_threads 1 --dbfilename="" &
PID=$!
sleep 2

# Trigger
```bash

sleep 1
if kill -0 $PID 2>/dev/null; then
    echo "PASS: Bug is fixed"
else
    echo "FAIL: Bug is present — process crashed"
fi
kill $PID 2>/dev/null
```

- **FAIL:** Process crashes (exit code != 0).
- **PASS:** Process returns error response, stays alive. `redis-cli -p 6379 PING` returns `PONG`.
