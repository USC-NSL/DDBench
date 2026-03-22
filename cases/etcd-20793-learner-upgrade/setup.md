# Setup: etcd #20793

## Project
- **Repository:** https://github.com/etcd-io/etcd
- **Language:** Go
- **Issue:** https://github.com/etcd-io/etcd/issues/20793
- **Fix PR:** https://github.com/etcd-io/etcd/pull/20797

## Clone and checkout buggy version
```bash
git clone https://github.com/etcd-io/etcd.git
cd etcd
# Checkout the commit just before the fix
git checkout 2e24a9845a3cd24fb52d676670e66c697f34336d~1
```

## Build multiple versions
This bug requires testing across etcd versions during rolling upgrades. You need binaries for 3.5.19, 3.5.21, and 3.6.4 (or whichever versions are relevant).

```bash
# Build the current (buggy) version
make build

# For multi-version testing, download specific release binaries:
# etcd 3.5.19
curl -L https://github.com/etcd-io/etcd/releases/download/v3.5.19/etcd-v3.5.19-linux-amd64.tar.gz -o /tmp/etcd-3.5.19.tar.gz
tar xzf /tmp/etcd-3.5.19.tar.gz -C /tmp/

# etcd 3.5.21
curl -L https://github.com/etcd-io/etcd/releases/download/v3.5.21/etcd-v3.5.21-linux-amd64.tar.gz -o /tmp/etcd-3.5.21.tar.gz
tar xzf /tmp/etcd-3.5.21.tar.gz -C /tmp/

# etcd 3.6.4
curl -L https://github.com/etcd-io/etcd/releases/download/v3.6.4/etcd-v3.6.4-linux-amd64.tar.gz -o /tmp/etcd-3.6.4.tar.gz
tar xzf /tmp/etcd-3.6.4.tar.gz -C /tmp/
```

## Cluster setup
Start a 3-node cluster using etcd 3.5.19 initially:
```bash
ETCD_BIN=/tmp/etcd-v3.5.19-linux-amd64/etcd

$ETCD_BIN --name node1 \
  --data-dir /tmp/etcd-upgrade-node1 \
  --listen-peer-urls http://127.0.0.1:2380 \
  --listen-client-urls http://127.0.0.1:2379 \
  --initial-advertise-peer-urls http://127.0.0.1:2380 \
  --advertise-client-urls http://127.0.0.1:2379 \
  --initial-cluster "node1=http://127.0.0.1:2380,node2=http://127.0.0.1:2382,node3=http://127.0.0.1:2384" &

$ETCD_BIN --name node2 \
  --data-dir /tmp/etcd-upgrade-node2 \
  --listen-peer-urls http://127.0.0.1:2382 \
  --listen-client-urls http://127.0.0.1:2381 \
  --initial-advertise-peer-urls http://127.0.0.1:2382 \
  --advertise-client-urls http://127.0.0.1:2381 \
  --initial-cluster "node1=http://127.0.0.1:2380,node2=http://127.0.0.1:2382,node3=http://127.0.0.1:2384" &

$ETCD_BIN --name node3 \
  --data-dir /tmp/etcd-upgrade-node3 \
  --listen-peer-urls http://127.0.0.1:2384 \
  --listen-client-urls http://127.0.0.1:2383 \
  --initial-advertise-peer-urls http://127.0.0.1:2384 \
  --advertise-client-urls http://127.0.0.1:2383 \
  --initial-cluster "node1=http://127.0.0.1:2380,node2=http://127.0.0.1:2382,node3=http://127.0.0.1:2384" &
```
