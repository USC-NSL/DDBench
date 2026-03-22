# Reproduce: RocksDB #13652

## Step 1: Build RocksDB and test program
Follow setup.md to build RocksDB and compile the test program.

## Step 2: Run the basic test
```bash
rm -rf /tmp/rocksdb_export_test /tmp/rocksdb_export_output /tmp/rocksdb_export_verify
/tmp/test_export_cf
```

## Step 3: Concurrent write + export test
For more reliable reproduction, run exports concurrently with writes:

```bash
cat > /tmp/test_export_race.cc <<'EOF'
#include <rocksdb/db.h>
#include <rocksdb/options.h>
#include <rocksdb/utilities/checkpoint.h>
#include <iostream>
#include <thread>
#include <atomic>

int main() {
    rocksdb::Options options;
    options.create_if_missing = true;
    options.create_missing_column_families = true;

    std::vector<rocksdb::ColumnFamilyDescriptor> cf_descs = {
        {rocksdb::kDefaultColumnFamilyName, options},
        {"test_cf", options}
    };
    std::vector<rocksdb::ColumnFamilyHandle*> cf_handles;
    rocksdb::DB* db;

    rocksdb::DB::Open(options, "/tmp/rocksdb_export_race", cf_descs, &cf_handles, &db);

    std::atomic<int> counter{0};
    std::atomic<bool> stop{false};
    int missing_total = 0;

    // Writer thread
    std::thread writer([&]() {
        std::string value(256, 'v');
        while (!stop) {
            int i = counter.fetch_add(1);
            db->Put(rocksdb::WriteOptions(), cf_handles[1],
                    "key" + std::to_string(i), value);
        }
    });

    // Repeatedly export and check
    for (int trial = 0; trial < 20; trial++) {
        std::this_thread::sleep_for(std::chrono::milliseconds(100));

        // Flush some data
        db->Flush(rocksdb::FlushOptions(), cf_handles[1]);

        // Wait for more writes after flush
        std::this_thread::sleep_for(std::chrono::milliseconds(50));

        int snapshot_count = counter.load();

        // Export
        std::string export_dir = "/tmp/rocksdb_export_trial_" + std::to_string(trial);
        rocksdb::Checkpoint* cp;
        rocksdb::Checkpoint::Create(db, &cp);
        rocksdb::ExportImportFilesMetaData* meta = nullptr;
        auto s = cp->ExportColumnFamily(cf_handles[1], export_dir, &meta);

        if (s.ok() && meta) {
            // Import the exported data into a separate DB and verify keys
            rocksdb::Options verify_opts;
            verify_opts.create_if_missing = true;
            rocksdb::DB* verify_db;
            std::string verify_dir = export_dir + "_verify";
            rocksdb::DB::Open(verify_opts, verify_dir, &verify_db);

            rocksdb::ImportColumnFamilyOptions icf_opts;
            icf_opts.move_files = false;
            rocksdb::ColumnFamilyHandle* icf;
            auto is = verify_db->CreateColumnFamilyWithImport(
                rocksdb::ColumnFamilyOptions(), "imported", icf_opts, *meta, &icf);

            if (is.ok()) {
                int found = 0;
                for (int i = 0; i < snapshot_count; i++) {
                    std::string val;
                    is = verify_db->Get(rocksdb::ReadOptions(), icf,
                                "key" + std::to_string(i), &val);
                    if (is.ok()) found++;
                }
                if (found < snapshot_count) {
                    int missing = snapshot_count - found;
                    missing_total += missing;
                    std::cout << "Trial " << trial << ": MISSING " << missing
                              << " keys in export (found " << found << "/" << snapshot_count << ")" << std::endl;
                }
                verify_db->DestroyColumnFamilyHandle(icf);
            }
            delete verify_db;
            rocksdb::DestroyDB(verify_dir, verify_opts);
        }
        delete cp;
        delete meta;
    }

    stop = true;
    writer.join();

    if (missing_total > 0) {
        std::cout << "BUG CONFIRMED: Total missing keys across trials: " << missing_total << std::endl;
    } else {
        std::cout << "All exports complete" << std::endl;
    }

    for (auto h : cf_handles) db->DestroyColumnFamilyHandle(h);
    delete db;
    return missing_total > 0 ? 1 : 0;
}
EOF

g++ -o /tmp/test_export_race /tmp/test_export_race.cc \
  -I./include -L./build -lrocksdb -lpthread -ldl -lsnappy -lz -lbz2 -llz4 -lzstd

rm -rf /tmp/rocksdb_export_race /tmp/rocksdb_export_trial_*
/tmp/test_export_race
```

## Expected result (bug present)
Some trials report missing committed keys. The export does not include all data that was committed at the time of the export call.
