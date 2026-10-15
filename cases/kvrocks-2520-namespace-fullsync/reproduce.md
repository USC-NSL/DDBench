# Reproduce: Kvrocks #2520

## Prerequisites

Run inside `./bench.sh shell kvrocks-2520-namespace-fullsync`, from `/workspace/src`; `./bench.sh setup` has built Kvrocks at `build/kvrocks`, and `redis-cli` is available in the image.

## Step 1: Create config files

Namespace commands require authentication. Create master and slave configs:

```bash
# Master config
cat > /tmp/kvrocks-master.conf <<'EOF'
bind 0.0.0.0
port 12520
dir /tmp/kvrocks-master
log-dir /tmp/kvrocks-master/logs
requirepass foobared
masterauth foobared
EOF

# Slave config
cat > /tmp/kvrocks-slave.conf <<'EOF'
bind 0.0.0.0
port 12521
dir /tmp/kvrocks-slave
log-dir /tmp/kvrocks-slave/logs
requirepass foobared
masterauth foobared
EOF

mkdir -p /tmp/kvrocks-master/logs /tmp/kvrocks-slave/logs
```

## Step 2: Start master and add namespaces

```bash
./build/kvrocks -c /tmp/kvrocks-master.conf &
sleep 2

# Add two namespaces
redis-cli -p 12520 -a foobared NAMESPACE ADD ns1 token1
redis-cli -p 12520 -a foobared NAMESPACE ADD ns2 token2

# Verify all three namespaces exist
redis-cli -p 12520 -a foobared NAMESPACE GET '*'
```

## Step 3: Start slave and trigger full sync

```bash
./build/kvrocks -c /tmp/kvrocks-slave.conf &
sleep 2

# Trigger replication
redis-cli -p 12521 -a foobared SLAVEOF 127.0.0.1 12520
```

## Step 4: Wait for sync to complete

```bash
# Poll until master_link_status is "up"
watch -n 1 'redis-cli -p 12521 -a foobared INFO replication 2>/dev/null | grep master_link_status'
```

## Step 5: Check namespaces on slave

```bash
redis-cli -p 12521 -a foobared NAMESPACE GET '*'
```

## Expected result (bug present)

Only the default namespace is returned. `ns1` and `ns2` are missing from the output, even though the full sync transferred the namespace data to the slave's storage engine.

## Expected result (fixed)

All namespaces (`ns1`, `ns2`, and default) are returned immediately after full sync completes, without requiring a server restart.

## Oracle verdict

`./bench.sh reproduce kvrocks-2520-namespace-fullsync` rebuilds the worktree and runs the oracle (`reproduce.sh`):

- **FAIL** (exit 1): the injected Go test `TestDDBenchOracleNamespaceFullSync` (in `tests/gocase/unit/namespace`) fails: after a master and a replica with `repl-namespace-enabled yes` complete a full sync of 1024 keys of 128 KiB plus a namespace `foo` (token `bar`) added on the master, `NAMESPACE GET foo` on the replica errors or does not return `bar`, or the replication offsets do not match within 60 s. A worktree that does not build, a Kvrocks server that does not start, or an oracle test that does not compile or is skipped, is also FAIL.
- **PASS** (exit 0): the oracle test passes within its 120 s timeout: the replica returns `bar` for `NAMESPACE GET foo` after the full sync.
- **ERROR** (exit 2): `REBUILD.sh`, the built `build/kvrocks` binary, `inject_test.go` or `tests/gocase` is missing, or the test did not run because a Go module download failed (network).
