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
docker pull redpandadata/redpanda:v24.1.x  # Use version matching the buggy commit
```

## Server setup
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
EOF

rm -rf /tmp/redpanda-data
./build/release/bin/redpanda \
  --redpanda-cfg /tmp/redpanda.yaml \
  --smp 4 \
  --memory 4G &
```
