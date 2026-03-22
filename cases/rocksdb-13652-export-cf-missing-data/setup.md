# Setup: RocksDB #13652

## Project
- **Repository:** https://github.com/facebook/rocksdb
- **Language:** C++
- **Issue:** https://github.com/facebook/rocksdb/issues/13652

## Clone and checkout buggy version
```bash
git clone https://github.com/facebook/rocksdb.git
cd rocksdb
# The fix is commit 0119a8c78 ("Fix Checkpoint::ExportColumnFamily() returning staled data (#13654)")
# Checkout its parent to get the buggy version
git checkout 0119a8c78~1
```

## Build
```bash
# Install dependencies (Ubuntu/Debian)
sudo apt-get install -y \
  build-essential cmake libgflags-dev \
  libsnappy-dev zlib1g-dev libbz2-dev \
  liblz4-dev libzstd-dev

# Build
mkdir -p build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release -DWITH_TESTS=ON
make -j$(nproc)
cd ..
```

## Test program
Create a test program to reproduce the issue:
```bash
cat > /tmp/test_export_cf.cc <<'EOF'
#include <rocksdb/db.h>
#include <rocksdb/options.h>
#include <rocksdb/utilities/checkpoint.h>
#include <iostream>
#include <string>
#include <cassert>

int main() {
    rocksdb::Options options;
    options.create_if_missing = true;
    options.create_missing_column_families = true;

    std::vector<rocksdb::ColumnFamilyDescriptor> cf_descs;
    cf_descs.push_back(rocksdb::ColumnFamilyDescriptor(
        rocksdb::kDefaultColumnFamilyName, options));
    cf_descs.push_back(rocksdb::ColumnFamilyDescriptor("test_cf", options));

    std::vector<rocksdb::ColumnFamilyHandle*> cf_handles;
    rocksdb::DB* db;

    auto s = rocksdb::DB::Open(options, "/tmp/rocksdb_export_test",
                                cf_descs, &cf_handles, &db);
    if (!s.ok()) {
        // First time - open without CFs
        s = rocksdb::DB::Open(options, "/tmp/rocksdb_export_test", &db);
        assert(s.ok());
        rocksdb::ColumnFamilyHandle* cf;
        s = db->CreateColumnFamily(options, "test_cf", &cf);
        assert(s.ok());
        cf_handles.push_back(nullptr);  // default
        cf_handles.push_back(cf);
    }

    // Write data to the column family
    for (int i = 0; i < 1000; i++) {
        s = db->Put(rocksdb::WriteOptions(), cf_handles[1],
                    "key" + std::to_string(i),
                    "value" + std::to_string(i));
        assert(s.ok());
    }

    // Flush
    s = db->Flush(rocksdb::FlushOptions(), cf_handles[1]);
    assert(s.ok());

    // Write more data (stays in memtable)
    for (int i = 1000; i < 2000; i++) {
        s = db->Put(rocksdb::WriteOptions(), cf_handles[1],
                    "key" + std::to_string(i),
                    "value" + std::to_string(i));
        assert(s.ok());
    }

    // Export the column family
    rocksdb::Checkpoint* checkpoint;
    s = rocksdb::Checkpoint::Create(db, &checkpoint);
    assert(s.ok());

    rocksdb::ExportImportFilesMetaData* metadata = nullptr;
    s = checkpoint->ExportColumnFamily(
        cf_handles[1], "/tmp/rocksdb_export_output", &metadata);
    std::cout << "Export status: " << s.ToString() << std::endl;

    // Import the exported data into a fresh DB and verify all keys are present
    rocksdb::Options import_options;
    import_options.create_if_missing = true;
    rocksdb::DB* verify_db;
    s = rocksdb::DB::Open(import_options, "/tmp/rocksdb_export_verify", &verify_db);
    assert(s.ok());

    // Import the exported column family
    rocksdb::ImportColumnFamilyOptions import_cf_options;
    import_cf_options.move_files = false;
    rocksdb::ColumnFamilyHandle* import_cf;
    s = verify_db->CreateColumnFamilyWithImport(
        rocksdb::ColumnFamilyOptions(), "imported_cf", import_cf_options, *metadata, &import_cf);
    std::cout << "Import status: " << s.ToString() << std::endl;

    // Verify all 2000 keys are present in the IMPORTED data (not the source DB)
    int found = 0;
    if (s.ok()) {
        for (int i = 0; i < 2000; i++) {
            std::string val;
            s = verify_db->Get(rocksdb::ReadOptions(), import_cf,
                        "key" + std::to_string(i), &val);
            if (s.ok()) found++;
        }
    }
    std::cout << "Found " << found << " of 2000 keys in exported data" << std::endl;
    if (found < 2000) {
        std::cout << "BUG: Export is missing " << (2000 - found)
                  << " committed keys (memtable data not exported)!" << std::endl;
    }

    // Cleanup
    for (auto h : cf_handles) if (h) db->DestroyColumnFamilyHandle(h);
    delete checkpoint;
    delete metadata;
    delete db;
    if (import_cf) verify_db->DestroyColumnFamilyHandle(import_cf);
    delete verify_db;
    return found < 2000 ? 1 : 0;
}
EOF

g++ -o /tmp/test_export_cf /tmp/test_export_cf.cc \
  -I./include -L./build -lrocksdb -lpthread -ldl -lsnappy -lz -lbz2 -llz4 -lzstd
```
