# Setup: ScyllaDB #28200

## Project
- **Repository:** https://github.com/scylladb/scylladb
- **Language:** C++
- **Issue:** https://github.com/scylladb/scylladb/issues/28200

## Clone and checkout buggy version
```bash
git clone https://github.com/scylladb/scylladb.git
cd scylladb
# Checkout a version containing the bug (before the fix for #28200)
git log --oneline --all --grep="28200" | head -5
# Use a commit before the fix
git checkout <buggy-commit>
git submodule update --init --recursive
```

## Build
```bash
# Install dependencies (Ubuntu 22.04/24.04)
sudo ./install-dependencies.sh

# Configure and build with ASAN (required to detect the UAF)
./configure.py --mode=dev --enable-asan
ninja build/dev/scylla
```

For a release build (the UAF may not crash without ASAN):
```bash
./configure.py --mode=release
ninja build/release/scylla
```

## Cluster setup
A multi-node cluster is needed to trigger streaming (topology changes):
```bash
# Use the scylla-ccm tool for local cluster management
pip install scylla-ccm

# Create a 3-node cluster
ccm create scylla-uaf -v release:5.4 -n 3 --scylla
ccm start

# Alternatively, start manually:
# Node 1
./build/dev/scylla --workdir /tmp/scylla-node1 \
  --smp 2 --memory 2G \
  --api-address 127.0.0.1 --api-port 10000 \
  --rpc-address 127.0.0.1 --listen-address 127.0.0.1 \
  --seed-provider-parameters seeds=127.0.0.1 \
  --native-transport-port 9042 &

# Node 2 (on different ports)
./build/dev/scylla --workdir /tmp/scylla-node2 \
  --smp 2 --memory 2G \
  --api-address 127.0.0.2 --api-port 10000 \
  --rpc-address 127.0.0.2 --listen-address 127.0.0.2 \
  --seed-provider-parameters seeds=127.0.0.1 \
  --native-transport-port 9042 &
```
