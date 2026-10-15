# Reproduce: NATS Server #7308

## Step 1: Start a 3-node NATS cluster

```bash
for i in 1 2 3; do
cat > /tmp/nats-del-n${i}.conf <<CONF
port: $((4240 + i))
server_name: del-n${i}
jetstream {
  store_dir: /tmp/nats-del-test/n${i}
  max_mem: 64MB
  max_file: 256MB
}
cluster {
  name: del-cluster
  listen: 0.0.0.0:$((6240 + i))
  routes: [
    nats-route://127.0.0.1:6241
    nats-route://127.0.0.1:6242
    nats-route://127.0.0.1:6243
  ]
}
CONF
done

rm -rf /tmp/nats-del-test
for i in 1 2 3; do
  ./nats-server -c /tmp/nats-del-n${i}.conf &
done
sleep 3
```

## Step 2: Create a stream with R3 replication

```bash
export NATS_URL=nats://127.0.0.1:4241

nats stream add TEST \
  --subjects="foo" \
  --replicas=3 \
  --storage=file \
  --discard=old \
  --max-msgs=-1 \
  --max-bytes=-1 \
  --max-age=-1 \
  --defaults
```

## Step 3: Publish a single message

```bash
nats pub foo "hello"
```

## Step 4: Delete a non-existent sequence (triggers the bug)

```bash
# Delete seq 2, which does not exist (only seq 1 exists)
# This triggers the cluster state reset
nats stream rmm TEST 2 -f
```

## Step 5: Observe the stream become inaccessible

```bash
# Immediately after the delete, check stream info
# The stream will be inaccessible for several seconds
nats stream info TEST
```

## Expected result (bug present)

The `nats stream rmm` command hangs for several seconds, then reports a timeout. The stream shows as "Inaccessible" during this period. A leader election is triggered, disrupting all operations on the stream.

## Expected result (bug fixed)

The `nats stream rmm` command immediately returns an error message (e.g., "message delete failed") without disrupting the cluster or triggering a leader election.

## Oracle verdict

`./bench.sh reproduce nats-7308-delete-nonexistent-reset` rebuilds the worktree and runs the oracle (`reproduce.sh`):

- **FAIL** (exit 1): for an R1 or an R3 stream holding one message in a 3-node cluster, a message-delete request does not get the expected reply, e.g. deleting sequence 2 (past the end of the stream) times out instead of returning a "message delete failed" (`ErrStoreEOF`) error. A worktree that does not build, or an oracle test that does not compile or is skipped, is also FAIL.
- **PASS** (exit 0): for both R1 and R3, deleting sequence 0 or an already-deleted sequence returns "no message found", deleting sequence 1 succeeds, and deleting sequence 2 returns "message delete failed" (`ErrStoreEOF`).
- **ERROR** (exit 2): the case is not set up (`REBUILD.sh` or the `nats-server` binary is missing), or Go module downloads fail so the oracle test cannot run.
