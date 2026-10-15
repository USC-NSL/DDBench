# Reproduce: etcd #19172

## Step 1: Run the embed integration test with race detector

```bash
cd /workspace/src
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

## Oracle verdict

`./bench.sh reproduce etcd-19172-embed-data-race` rebuilds the worktree and runs the oracle (`reproduce.sh`):

- **FAIL** (exit 1): the Go race detector reports `WARNING: DATA RACE` in any of 10 runs of the `TestEmbedEtcd*` tests in `tests/integration/embed` (`-race -count=3` each, 30 executions in total), or one of those tests fails. A worktree that does not build, or tests that do not compile or do not run, is also FAIL.
- **PASS** (exit 0): all 10 runs complete with at least one `TestEmbedEtcd*` test passing, none failing, and no data race reported.
- **ERROR** (exit 2): the case is not set up (`REBUILD.sh`, the etcd source or `tests/integration/embed` is missing), or Go module downloads fail so the tests cannot run.
