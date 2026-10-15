# Crash Output

Obtained by starting `./build/kvrocks --port 6666 --dir /tmp/kvrocks_data --log-dir /tmp/kvrocks_data` and sending `redis-cli -p 6666 ZDIFF 0 a`.

## Output

```
Sending: ZDIFF 0 a
Segmentation fault      (core dumped)
```
