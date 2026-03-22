# Setup: ScyllaDB #27956

## Project
- **Repository:** https://github.com/scylladb/scylladb
- **Language:** C++
- **Issue:** https://github.com/scylladb/scylladb/issues/27956

## Clone and checkout buggy version
```bash
git clone https://github.com/scylladb/scylladb.git
cd scylladb
# The regression was introduced in commit 5d1f74b86ac6ef151871ee300f8728
# Checkout that commit or a version containing it
git checkout 5d1f74b86ac6ef151871ee300f8728
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
A single node is sufficient to reproduce this bug, but the schema requires a materialized view:
```bash
./build/dev/scylla --workdir /tmp/scylla-staging \
  --smp 2 --memory 2G \
  --api-address 127.0.0.1 --api-port 10000 \
  --rpc-address 127.0.0.1 --listen-address 127.0.0.1 \
  --seed-provider-parameters seeds=127.0.0.1 \
  --native-transport-port 9042 &
```

For multi-node (closer to production scenario):
```bash
pip install scylla-ccm
ccm create scylla-staging -v release:5.4 -n 2 --scylla
ccm start
```

## Important: Docker/ccm release versions will not work

**This bug is a regression introduced by commit `5d1f74b86ac6ef151871ee300f8728`**, which reordered view update generator initialization before SSTable loading. This commit is not present in any published Docker release (e.g., `5.4.0`, `6.2.x`). Building from source at the exact regression commit is required. The ccm `release:5.4` shortcut will use a release that does not contain the regression.
