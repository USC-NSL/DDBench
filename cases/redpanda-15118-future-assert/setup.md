# Setup: Redpanda #15118

## Project
- **Repository:** https://github.com/redpanda-data/redpanda
- **Language:** C++
- **Issue:** https://github.com/redpanda-data/redpanda/issues/15118
- **Fix PR:** https://github.com/redpanda-data/redpanda/pull/15414

## Clone and checkout buggy version
```bash
git clone https://github.com/redpanda-data/redpanda.git
cd redpanda
# Checkout the commit just before the fix
git checkout 6cd0e7054aada957dc28b6826b6f4f77ea6eb40e~1
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

# Build using the Redpanda build system
mkdir -p build/release
cd build/release
cmake ../.. -GNinja -DCMAKE_BUILD_TYPE=Release
ninja redpanda
cd ../..
```

Alternatively, use the Redpanda Docker image:
```bash
# Use the Docker image matching the buggy version
docker pull redpandadata/redpanda:v23.3.x  # Use version matching the buggy commit
```

## Cluster setup
```bash
# Single-node for reproduction (the bug does not require multi-node)
./build/release/bin/redpanda \
  --redpanda-cfg /tmp/redpanda.yaml \
  --smp 2 \
  --memory 2G &
```
