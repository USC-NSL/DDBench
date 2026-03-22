# Verification: Dragonfly #6766

```bash
#!/bin/bash

./build-dbg/dragonfly --port 6379 --logtostderr --proactor_threads 1 --dbfilename="" &
PID=$!
sleep 2

# Rapid JSON.SET + DEL cycles on nested structures
for i in $(seq 1 500); do
  redis-cli -p 6379 JSON.SET mykey '.' '{"a":{"b":{"c":"val","d":[1,2,3]},"e":{"f":"val2"}}}' > /dev/null 2>&1
  redis-cli -p 6379 JSON.SET mykey '$.a.b' '{"new":"data","nested":{"x":1}}' > /dev/null 2>&1
  redis-cli -p 6379 DEL mykey > /dev/null 2>&1
  if ! kill -0 $PID 2>/dev/null; then
    echo "FAIL: Bug is present — process crashed during JSON SET/DEL cycle $i"
    exit 1
  fi
done

if kill -0 $PID 2>/dev/null; then
    echo "PASS: Bug is fixed — process survived 500 JSON SET/DEL cycles"
else
    echo "FAIL: Bug is present — process crashed"
fi

kill $PID 2>/dev/null
```

- **FAIL:** Process crashes at `json_family.cc:99`.
- **PASS:** Process stays alive after all cycles complete.
