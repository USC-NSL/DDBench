#!/usr/bin/env bash
# Setup script for rocksdb-10751-stalled-writes-shutdown
# Clones the repository, checks out the buggy commit, builds RocksDB,
# and compiles the test program.
set -euo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/rocksdb-10751-stalled-writes-shutdown"
BUGGY_COMMIT="a45e6878f39cdc777c54e5d6749d53c1f70e2b52~1"
REPO_URL="https://github.com/facebook/rocksdb.git"

echo "=== Setting up rocksdb-10751-stalled-writes-shutdown ==="

# Install dependencies
echo "Installing build dependencies..."
sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    build-essential cmake git \
    libgflags-dev libsnappy-dev zlib1g-dev libbz2-dev liblz4-dev libzstd-dev liburing-dev

# Check prerequisites
for cmd in git cmake g++; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: $cmd is required but not installed."
        exit 1
    fi
done

# Clone
if [ ! -d "$WORK_DIR" ]; then
    echo "Cloning repository..."
    git clone "$REPO_URL" "$WORK_DIR"
fi

cd "$WORK_DIR"

# Checkout buggy commit
echo "Checking out buggy commit..."
git checkout $BUGGY_COMMIT 2>/dev/null || git checkout $(git rev-parse $BUGGY_COMMIT)

# Build RocksDB
if [ ! -f "$WORK_DIR/build/librocksdb.a" ]; then
    echo "Building RocksDB (this may take several minutes)..."
    mkdir -p build && cd build
    cmake .. \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_CXX_FLAGS="-include cstdint -w" \
        -DFAIL_ON_WARNINGS=OFF \
        -DWITH_TESTS=OFF
    make -j$(nproc) rocksdb
    cd "$WORK_DIR"
else
    echo "Library already built, skipping build."
fi

# Create test program
echo "Creating test program..."
cat > "$WORK_DIR/test_stall_shutdown.cc" <<CPPEOF
#include <rocksdb/db.h>
#include <rocksdb/options.h>
#include <rocksdb/rate_limiter.h>
#include <iostream>
#include <string>

int main() {
    rocksdb::Options options;
    options.create_if_missing = true;
    // Set a very low write rate to force stalling
    options.rate_limiter.reset(
        rocksdb::NewGenericRateLimiter(1024));  // 1KB/s
    options.write_buffer_size = 64 * 1024;  // 64KB
    options.max_write_buffer_number = 2;
    options.level0_slowdown_writes_trigger = 2;
    options.level0_stop_writes_trigger = 4;

    rocksdb::DB* db;
    auto s = rocksdb::DB::Open(options, "/tmp/rocksdb_stall_test_db", &db);
    if (!s.ok()) {
        std::cerr << "Failed to open: " << s.ToString() << std::endl;
        return 1;
    }

    // Write enough data to trigger write stall
    std::string value(4096, 'x');
    for (int i = 0; i < 10000; i++) {
        s = db->Put(rocksdb::WriteOptions(),
                    "key" + std::to_string(i), value);
        if (!s.ok()) {
            std::cerr << "Put failed: " << s.ToString() << std::endl;
            break;
        }
    }

    // Try to close while writes may be stalled
    std::cout << "Calling Close()..." << std::endl;
    s = db->Close();
    std::cout << "Close() returned: " << s.ToString() << std::endl;
    delete db;
    return 0;
}
CPPEOF

# Compile test program
echo "Compiling test program..."
g++ -o "$WORK_DIR/test_stall_shutdown" "$WORK_DIR/test_stall_shutdown.cc" \
    -std=c++17 \
    -I"$WORK_DIR/include" \
    -L"$WORK_DIR/build" \
    -lrocksdb \
    -lpthread -ldl -lsnappy -lz -lbz2 -llz4 -lzstd -luring

echo ""
echo "=== Setup complete ==="
echo "Binary: $WORK_DIR/test_stall_shutdown"
