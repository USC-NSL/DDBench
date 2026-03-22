# Verification: Dragonfly #6761

```bash
./build-dbg/dragonfly --port 6379 --memcached_port=11211 --logtostderr --proactor_threads 1 --dbfilename="" --max_bulk_len=1048576 &
PID=$!
sleep 2

# Trigger
Download the crash archive from the issue and replay:

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
