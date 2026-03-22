# Setup: RocksDB #10751

## Project
- **Repository:** https://github.com/facebook/rocksdb
- **Language:** C++
- **Issue:** https://github.com/facebook/rocksdb/issues/10751

## Clone and checkout buggy version
```bash
git clone https://github.com/facebook/rocksdb.git
cd rocksdb
# Checkout the commit just before the fix
git checkout a45e6878f39cdc777c54e5d6749d53c1f70e2b52~1
```

## Build
```bash
# Install dependencies (Ubuntu/Debian)
sudo apt-get install -y \
  build-essential cmake libgflags-dev \
  libsnappy-dev zlib1g-dev libbz2-dev \
  liblz4-dev libzstd-dev

# Build as shared library
mkdir -p build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release -DWITH_TESTS=ON
make -j$(nproc) rocksdb db_bench
cd ..

# Or build using make
make -j$(nproc) shared_lib db_bench
```

## Test program
Create a minimal C++ test program to reproduce the issue:
```bash
cat > /tmp/test_stall_shutdown.cc <<'EOF'
#include <rocksdb/db.h>
#include <rocksdb/options.h>
#include <rocksdb/rate_limiter.h>
#include <iostream>
#include <thread>
#include <chrono>

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
    auto s = rocksdb::DB::Open(options, "/tmp/rocksdb_stall_test", &db);
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
EOF

# Compile test program
g++ -o /tmp/test_stall_shutdown /tmp/test_stall_shutdown.cc \
  -I./include -L./build -lrocksdb -lpthread -ldl -lsnappy -lz -lbz2 -llz4 -lzstd
```
