# Reproduce: Kvrocks #2520

## Prerequisites

A Kvrocks build at the buggy commit with `redis-cli` available (from redis-tools package).

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
