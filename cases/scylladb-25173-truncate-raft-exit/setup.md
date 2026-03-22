# Setup: ScyllaDB #25173

## Project
- **Repository:** https://github.com/scylladb/scylladb
- **Language:** C++
- **Issue:** https://github.com/scylladb/scylladb/issues/25173
- **Fix PR:** https://github.com/scylladb/scylladb/pull/25174

## Clone and checkout buggy version
```bash
git clone https://github.com/scylladb/scylladb.git
cd scylladb
# Checkout the commit just before the fix
git checkout bb922b2aa9dd58de902848d99fde06b9b1c5828a~1
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
A single-node cluster suffices for reproduction, but a multi-node cluster (with raft) is closer to production:
```bash
# Single node
./build/dev/scylla --workdir /tmp/scylla-truncate \
  --smp 2 --memory 2G \
  --api-address 127.0.0.1 --api-port 10000 \
  --rpc-address 127.0.0.1 --listen-address 127.0.0.1 \
  --seed-provider-parameters seeds=127.0.0.1 \
  --native-transport-port 9042 &
```

For multi-node (recommended):
```bash
# Use ccm
pip install scylla-ccm
ccm create scylla-truncate -v release:5.4 -n 3 --scylla
ccm start
```

## Important: Docker/ccm release versions may not work

**This bug exists only in development builds** where the truncate check calls `on_internal_error` (which throws). Published Docker images and ccm release versions (e.g., `release:5.4`) use `SCYLLA_ASSERT` instead, which is a different code path that does not trigger the raft applier exit. Building from source at the exact buggy commit (`bb922b2aa9dd58de902848d99fde06b9b1c5828a~1`) is required for reliable reproduction.
