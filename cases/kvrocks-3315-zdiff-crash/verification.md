# Verification: Kvrocks #3315

```bash
./bin/kvrocks -p 6666 --dir /tmp/kvrocks_data &
PID=$!
sleep 2
redis-cli -p 6666 ZDIFF 0 a 2>/dev/null
sleep 1
if kill -0 $PID 2>/dev/null; then
    echo "PASS: Bug is fixed — process survived"
else
    echo "FAIL: Bug is present — process crashed"
fi
kill $PID 2>/dev/null
rm -rf /tmp/kvrocks_data
```

- **FAIL:** Process crashes on `ZDIFF 0 a`.
- **PASS:** Process returns error like "ERR at least 1 input key is needed" and stays alive.
