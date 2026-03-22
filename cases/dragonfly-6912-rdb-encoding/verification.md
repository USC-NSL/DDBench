# Verification: Dragonfly #6912

```bash
#!/bin/bash

./build-dbg/dragonfly --port 6379 --logtostderr --proactor_threads 1 --dbfilename="" &
PID=$!
sleep 2

# Create a CMS key
redis-cli -p 6379 CMS.INITBYPROB mysketch 0.001 0.01
redis-cli -p 6379 CMS.INCRBY mysketch item1 5 item2 10

# Try to DUMP it
redis-cli -p 6379 DUMP mysketch 2>/dev/null

sleep 1
if kill -0 $PID 2>/dev/null; then
    echo "PASS: Bug is fixed — DUMP on CMS key did not crash"
else
    echo "FAIL: Bug is present — process crashed on DUMP of CMS key"
fi

kill $PID 2>/dev/null
```

- **FAIL:** Process crashes with `Unknown encoding 0 for type 17`.
- **PASS:** Process stays alive; DUMP returns serialized data or a handled error.
