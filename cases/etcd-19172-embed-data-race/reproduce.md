# Reproduce: etcd #19172

## Step 1: Run the embed integration test with race detector

```bash
cd etcd
go test -race -run TestEmbedEtcd ./tests/integration/embed/ -count=1
```

If the race does not trigger on the first run, repeat several times:
```bash
for i in $(seq 1 10); do
  echo "=== Run $i ==="
  go test -race -run TestEmbedEtcd ./tests/integration/embed/ -count=1 2>&1 | grep -A 20 "DATA RACE" && break
done
```

## Expected result (bug present)
The test outputs a `WARNING: DATA RACE` showing a write in `embed.(*Etcd).Close()` at `server/embed/etcd.go:460` racing with a read in `embed.(*Etcd).errHandler()` at `server/embed/etcd.go:875`. The test fails with `race detected during execution of test`.
