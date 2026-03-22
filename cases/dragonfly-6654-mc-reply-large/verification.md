# Verification: Dragonfly #6654

```bash
#!/bin/bash

./build-dbg/dragonfly --port 6379 --memcached_port=11211 --max_bulk_len=1048576 --logtostderr --proactor_threads 1 --dbfilename="" &
PID=$!
sleep 2

# Store a large value
redis-cli -p 6379 SET bigkey "$(python3 -c "print('A' * 8000)")"
sleep 1

# Retrieve via memcached meta get
echo -e "mg bigkey v\r\nquit\r\n" | nc -w 3 127.0.0.1 11211 > /dev/null 2>&1
sleep 1

if kill -0 $PID 2>/dev/null; then
    echo "PASS: Bug is fixed — process survived large memcached meta get"
else
    echo "FAIL: Bug is present — process crashed on large memcached meta get reply"
fi

kill $PID 2>/dev/null
```

- **FAIL:** Process crashes (buffer capacity exceeded assertion).
- **PASS:** Process stays alive, meta get returns the value or an error gracefully.
