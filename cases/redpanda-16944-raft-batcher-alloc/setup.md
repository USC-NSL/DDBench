# Setup: Redpanda #16944

## Project
- **Repository:** https://github.com/redpanda-data/redpanda
- **Language:** C++
- **Issue:** https://github.com/redpanda-data/redpanda/issues/16944
- **Fix PR:** https://github.com/redpanda-data/redpanda/pull/17425

## Clone and checkout buggy version
```bash
git clone https://github.com/redpanda-data/redpanda.git
cd redpanda
# Checkout the commit just before the fix
git checkout 952b8c96298380b5986e4dfe71dba5616a2495b3~1
git submodule update --init --recursive
```

## Build
```bash
# Install dependencies (Ubuntu/Debian)
sudo apt-get install -y \
  build-essential cmake ninja-build \
  libboost-all-dev libseastar-dev \
  ragel libhwloc-dev libnuma-dev \
  libpciaccess-dev libcrypto++-dev \
  libsctp-dev libxml2-dev xfslibs-dev \
  systemtap-sdt-dev libtool libyaml-cpp-dev \
  libfmt-dev libprotobuf-dev protobuf-compiler \
  pkg-config python3 python3-jinja2

# Build
mkdir -p build/release
cd build/release
cmake ../.. -GNinja -DCMAKE_BUILD_TYPE=Release
ninja redpanda
cd ../..
```

Alternatively, use Docker:
```bash
# Use v23.3.1 or v23.3.2 — NOT v24.1.1+ which already contains the fix
docker pull redpandadata/redpanda:v23.3.1
```

## Server setup (source build)
```bash
cat > /tmp/redpanda.yaml <<EOF
redpanda:
  data_directory: /tmp/redpanda-data
  node_id: 0
  rpc_server:
    address: "0.0.0.0"
    port: 33145
  kafka_api:
    address: "0.0.0.0"
    port: 9092
  admin:
    address: "0.0.0.0"
    port: 9644
  developer_mode: true
  memory_allocation_warning_threshold: 131073
EOF

rm -rf /tmp/redpanda-data
./build/release/bin/redpanda \
  --redpanda-cfg /tmp/redpanda.yaml \
  --smp 1 \
  --memory 4G &
```

**Note:** `memory_allocation_warning_threshold: 131073` must be set in the config — in v23.3.x it defaults to disabled (nullopt), so the oversized allocation warning is never emitted even when allocations exceed 128KB. Use `--smp 1` to concentrate all raft batching on a single Seastar core.

## Server setup (Docker — recommended)
```bash
docker run -d --name redpanda --network host \
  redpandadata/redpanda:v23.3.1 \
  redpanda start --smp 1 --memory 2G --overprovisioned \
  --advertise-kafka-addr localhost:9092 \
  --set redpanda.memory_allocation_warning_threshold=131073
```
