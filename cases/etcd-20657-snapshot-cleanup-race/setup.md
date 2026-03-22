# Setup: etcd #20657

## Project
- **Repository:** https://github.com/etcd-io/etcd
- **Language:** Go
- **Issue:** https://github.com/etcd-io/etcd/issues/20657

## Clone and checkout buggy version
```bash
git clone https://github.com/etcd-io/etcd.git
cd etcd
# Checkout a version prior to the fix for issue #20657
git log --oneline --all --grep="20657" | head -5
# Use a commit before the fix was merged
git checkout main~50  # Adjust based on when the fix landed
```

## Build
```bash
# Requires Go 1.22+
make build
```

The built binaries will be in `bin/`:
- `bin/etcd` — the etcd server
- `bin/etcdctl` — the etcd CLI client
- `bin/etcdutl` — the etcd utility

## Cluster setup
Start a 3-node cluster for reproduction:
```bash
# Node 1
bin/etcd --name node1 \
  --data-dir /tmp/etcd-node1 \
  --listen-peer-urls http://127.0.0.1:2380 \
  --listen-client-urls http://127.0.0.1:2379 \
  --initial-advertise-peer-urls http://127.0.0.1:2380 \
  --advertise-client-urls http://127.0.0.1:2379 \
  --initial-cluster "node1=http://127.0.0.1:2380,node2=http://127.0.0.1:2382,node3=http://127.0.0.1:2384" \
  --snapshot-count=2 &

# Node 2
bin/etcd --name node2 \
  --data-dir /tmp/etcd-node2 \
  --listen-peer-urls http://127.0.0.1:2382 \
  --listen-client-urls http://127.0.0.1:2381 \
  --initial-advertise-peer-urls http://127.0.0.1:2382 \
  --advertise-client-urls http://127.0.0.1:2381 \
  --initial-cluster "node1=http://127.0.0.1:2380,node2=http://127.0.0.1:2382,node3=http://127.0.0.1:2384" \
  --snapshot-count=2 &

# Node 3
bin/etcd --name node3 \
  --data-dir /tmp/etcd-node3 \
  --listen-peer-urls http://127.0.0.1:2384 \
  --listen-client-urls http://127.0.0.1:2383 \
  --initial-advertise-peer-urls http://127.0.0.1:2384 \
  --advertise-client-urls http://127.0.0.1:2383 \
  --initial-cluster "node1=http://127.0.0.1:2380,node2=http://127.0.0.1:2382,node3=http://127.0.0.1:2384" \
  --snapshot-count=2 &
```
