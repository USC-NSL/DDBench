# Reproduce: RocksDB #10751

## Step 1: Build RocksDB and test program
Run inside `./bench.sh shell rocksdb-10751-stalled-writes-shutdown`, from `/workspace/src`. `./bench.sh setup` has already built the static library `build/librocksdb.a` (Release). Compile the case's test program (the same harness the automated oracle uses) against it:

```bash
cd /workspace/src
g++ -std=c++17 -O1 -include cstdint -w -I./include /bench/test_stall_shutdown.cc build/librocksdb.a \
  -lpthread -ldl -lsnappy -lz -lbz2 -llz4 -lzstd -luring -lgflags -o /tmp/test_stall_shutdown
```

The program prints its own `PASS`/`FAIL`/`ERROR` line and exits 0/1/2; it uses `/tmp/ddbench-stall-db` unless a DB path is given as its first argument.

## Step 2: Run the test program
```bash
rm -rf /tmp/ddbench-stall-db
timeout 60 /tmp/test_stall_shutdown
EXIT_CODE=$?

if [ $EXIT_CODE -eq 124 ] || [ $EXIT_CODE -eq 1 ]; then
  echo "BUG CONFIRMED: Close() hung — timed out after 60 seconds"
elif [ $EXIT_CODE -eq 0 ]; then
  echo "Close() completed normally"
else
  echo "Unexpected exit code: $EXIT_CODE"
fi
```

## Alternative reproduction using db_bench
`./bench.sh setup` builds only the library, so build the tool first:

```bash
make -C build -j$(nproc) db_bench
rm -rf /tmp/rocksdb_stall_bench

# Start db_bench with aggressive stall settings
timeout 120 ./build/db_bench \
  --benchmarks=fillrandom \
  --db=/tmp/rocksdb_stall_bench \
  --num=1000000 \
  --value_size=4096 \
  --write_buffer_size=65536 \
  --max_write_buffer_number=2 \
  --level0_slowdown_writes_trigger=2 \
  --level0_stop_writes_trigger=4 \
  --rate_limiter_bytes_per_sec=1024 \
  --threads=4

# If the benchmark hangs during cleanup/close, the bug is present
```

## Step 3: Alternative multi-threaded reproduction
```bash
cat > /tmp/test_stall_mt.cc <<'EOF'
#include <rocksdb/db.h>
#include <rocksdb/options.h>
#include <rocksdb/rate_limiter.h>
#include <iostream>
#include <thread>
#include <vector>
#include <atomic>

int main() {
    rocksdb::Options options;
    options.create_if_missing = true;
    options.rate_limiter.reset(rocksdb::NewGenericRateLimiter(1024));
    options.write_buffer_size = 64 * 1024;
    options.max_write_buffer_number = 2;
    options.level0_slowdown_writes_trigger = 2;
    options.level0_stop_writes_trigger = 4;

    rocksdb::DB* db;
    rocksdb::DB::Open(options, "/tmp/rocksdb_stall_mt", &db);

    std::atomic<bool> stop{false};
    std::vector<std::thread> writers;
    std::string value(4096, 'x');

    // Launch writer threads
    for (int t = 0; t < 4; t++) {
        writers.emplace_back([&, t]() {
            for (int i = 0; !stop; i++) {
                db->Put(rocksdb::WriteOptions(),
                        "t" + std::to_string(t) + "_k" + std::to_string(i),
                        value);
            }
        });
    }

    // Let writes accumulate and stall
    std::this_thread::sleep_for(std::chrono::seconds(10));

    // Signal stop and close — this hangs with the bug
    stop = true;
    std::cout << "Calling Close()..." << std::endl;
    db->Close();
    std::cout << "Close() returned" << std::endl;

    for (auto& w : writers) w.join();
    delete db;
    return 0;
}
EOF

g++ -std=c++17 -include cstdint -w -o /tmp/test_stall_mt /tmp/test_stall_mt.cc \
  -I./include -L./build -lrocksdb -lpthread -ldl -lsnappy -lz -lbz2 -llz4 -lzstd -luring -lgflags
rm -rf /tmp/rocksdb_stall_mt
timeout 60 /tmp/test_stall_mt
```

## Expected result (bug present)
`DB::Close()` hangs indefinitely. The process never prints "Close() returned" and must be killed.

## Oracle verdict

`./bench.sh reproduce rocksdb-10751-stalled-writes-shutdown` rebuilds the worktree and runs the oracle (`reproduce.sh`), which compiles the case's harness `test_stall_shutdown.cc` against the rebuilt `build/librocksdb.a` and runs it:

- **FAIL** (exit 1): with writes stopped at `level0_stop_writes_trigger` (20 L0 files) and a writer blocked in `Put`, the blocked write does not return within 30 s after `CancelAllBackgroundWork` starts the shutdown, or the harness hangs past 300 s or crashes. A worktree that does not build, a harness that does not compile or link against the worktree's `build/librocksdb.a`, or a `DB::Open`/`Put`/`Flush` failure in the harness, is also FAIL.
- **PASS** (exit 0): the blocked write returns with a non-OK status after shutdown begins.
- **ERROR** (exit 2): `REBUILD.sh`, `build/librocksdb.a` or `test_stall_shutdown.cc` is missing, or the harness cannot establish the stall (fewer than 20 L0 files, writes never stopped, the write completes before shutdown, or the blocked write returns OK).
