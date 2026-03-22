# Setup: ScyllaDB #28057

## Project
- **Repository:** https://github.com/scylladb/scylladb
- **Language:** C++
- **Issue:** https://github.com/scylladb/scylladb/issues/28057
- **Fix PR:** https://github.com/scylladb/scylladb/pull/27435

## Clone and checkout buggy version
```bash
git clone https://github.com/scylladb/scylladb.git
cd scylladb
# Checkout the commit just before the fix
git checkout af6cb0d0a431170d32ad7816c050f875298aa840~1
git submodule update --init --recursive
```

## Build
```bash
# Install dependencies (Ubuntu 22.04/24.04)
sudo ./install-dependencies.sh

# Build in dev mode
./configure.py --mode=dev
ninja build/dev/scylla
```

## Cluster setup
A multi-node cluster is required. Use at least 3 nodes:
**Note:** The ccm `release:5.4` shortcut may not contain this bug. The fix (`af6cb0d0a431`) was merged in January 2026 for a bug in the raft topology IP preservation logic. Building from source at commit `af6cb0d0a431~1` is required for reliable reproduction.

```bash
# Using ccm — only works if using a custom-built scylla binary
pip install scylla-ccm

ccm create scylla-replace -v release:5.4 -n 3 --scylla
ccm start

# Or start manually:
# Node 1
./build/dev/scylla --workdir /tmp/scylla-replace-node1 \
  --smp 2 --memory 2G \
  --api-address 127.0.0.1 --api-port 10000 \
  --rpc-address 127.0.0.1 --listen-address 127.0.0.1 \
  --seed-provider-parameters seeds=127.0.0.1 \
  --native-transport-port 9042 &

# Node 2
./build/dev/scylla --workdir /tmp/scylla-replace-node2 \
  --smp 2 --memory 2G \
  --api-address 127.0.0.2 --api-port 10000 \
  --rpc-address 127.0.0.2 --listen-address 127.0.0.2 \
  --seed-provider-parameters seeds=127.0.0.1 \
  --native-transport-port 9042 &

# Node 3
./build/dev/scylla --workdir /tmp/scylla-replace-node3 \
  --smp 2 --memory 2G \
  --api-address 127.0.0.3 --api-port 10000 \
  --rpc-address 127.0.0.3 --listen-address 127.0.0.3 \
  --seed-provider-parameters seeds=127.0.0.1 \
  --native-transport-port 9042 &
```
