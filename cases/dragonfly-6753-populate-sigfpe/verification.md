# Verification: Dragonfly #6753

```bash
./build-dbg/dragonfly --port 6379 --logtostderr --proactor_threads 1 --dbfilename="" &
PID=$!
sleep 2
redis-cli -p 6379 DEBUG POPULATE 100 prefix 0 2>/dev/null
sleep 1
if kill -0 $PID 2>/dev/null; then
    echo "PASS: Bug is fixed"
else
    echo "FAIL: Bug is present (SIGFPE crash)"
fi
kill $PID 2>/dev/null
```

- **FAIL:** Process crashes with SIGFPE.
- **PASS:** Process returns error message, stays alive. `PING` returns `PONG`.
