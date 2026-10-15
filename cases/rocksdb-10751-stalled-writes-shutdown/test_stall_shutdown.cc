// Oracle harness for rocksdb-10751-stalled-writes-shutdown (built by
// reproduce.sh outside the worktree, linked against the worktree's
// librocksdb.a).
//
// Scenario: a DB has as many L0 files as level0_stop_writes_trigger, so writes
// are stopped until compaction catches up. The single low-priority background
// thread is kept busy, so the compaction that would lift the stop cannot start.
// A writer thread blocks in the write stop, then the DB is shut down
// (CancelAllBackgroundWork, i.e. what DB::Close() does first). The stalled
// write must return (with an error) instead of blocking forever.
//
// Exit codes (DDBench contract): 0 PASS, 1 FAIL, 2 ERROR.
#include <rocksdb/convenience.h>
#include <rocksdb/db.h>
#include <rocksdb/env.h>
#include <rocksdb/options.h>

#include <unistd.h>

#include <atomic>
#include <chrono>
#include <cstdio>
#include <random>
#include <string>
#include <thread>

using ROCKSDB_NAMESPACE::DB;
using ROCKSDB_NAMESPACE::FlushOptions;
using ROCKSDB_NAMESPACE::Options;
using ROCKSDB_NAMESPACE::Status;
using ROCKSDB_NAMESPACE::WriteOptions;

static void finish(int code, const std::string& msg) {
  printf("%s\n", msg.c_str());
  fflush(stdout);
  _exit(code);  // no destructors: a stuck writer thread must not block exit
}

// Occupies the only LOW-priority background thread for a few seconds.
static void BlockLowPool(void*) { std::this_thread::sleep_for(std::chrono::seconds(6)); }

static int L0Files(DB* db) {
  std::string v;
  if (!db->GetProperty("rocksdb.num-files-at-level0", &v)) return -1;
  return std::stoi(v);
}

int main(int argc, char** argv) {
  const std::string path = argc > 1 ? argv[1] : "/tmp/ddbench-stall-db";
  const int kFiles = 20;
  ROCKSDB_NAMESPACE::DestroyDB(path, Options());

  // Phase 1: kFiles L0 files, no compaction.
  {
    Options o;
    o.create_if_missing = true;
    o.disable_auto_compactions = true;
    o.compression = ROCKSDB_NAMESPACE::kNoCompression;
    DB* db = nullptr;
    Status s = DB::Open(o, path, &db);
    if (!s.ok()) finish(1, "FAIL: DB::Open failed: " + s.ToString());
    std::mt19937 rng(403);
    std::string value(1000, '\0');
    for (int f = 0; f < kFiles; f++) {
      for (int k = 0; k < 100; k++) {
        for (auto& ch : value) ch = static_cast<char>(rng());
        // Same keys in every file: the L0 files overlap, so compaction has to
        // rewrite them (no trivial move).
        s = db->Put(WriteOptions(), "key_" + std::to_string(k), value);
        if (!s.ok()) finish(1, "FAIL: Put failed: " + s.ToString());
      }
      s = db->Flush(FlushOptions());
      if (!s.ok()) finish(1, "FAIL: Flush failed: " + s.ToString());
    }
    const int l0 = L0Files(db);
    printf("L0 files after setup: %d\n", l0);
    if (l0 < kFiles) finish(2, "ERROR: expected " + std::to_string(kFiles) + " L0 files, got " + std::to_string(l0));
    s = db->Close();
    delete db;
  }

  // Phase 2: reopen with writes stopped at kFiles L0 files. The compaction that
  // would lift the stop is queued behind a job that occupies the single
  // LOW-priority thread.
  ROCKSDB_NAMESPACE::Env* env = ROCKSDB_NAMESPACE::Env::Default();
  env->SetBackgroundThreads(1, ROCKSDB_NAMESPACE::Env::Priority::LOW);
  env->Schedule(&BlockLowPool, nullptr, ROCKSDB_NAMESPACE::Env::Priority::LOW);
  Options o;
  o.level0_slowdown_writes_trigger = kFiles;
  o.level0_stop_writes_trigger = kFiles;
  o.disable_auto_compactions = false;
  o.max_background_jobs = 2;
  o.compression = ROCKSDB_NAMESPACE::kNoCompression;
  DB* db = nullptr;
  Status s = DB::Open(o, path, &db);
  if (!s.ok()) finish(1, "FAIL: DB::Open (reopen) failed: " + s.ToString());

  std::atomic<bool> returned{false};
  Status write_status;
  std::thread writer([&] {
    write_status = db->Put(WriteOptions(), "stalled_key", "value");
    returned = true;
  });

  bool stopped = false;
  for (int i = 0; i < 100 && !stopped; i++) {
    std::string v;
    stopped = db->GetProperty("rocksdb.is-write-stopped", &v) && v == "1";
    if (!stopped) std::this_thread::sleep_for(std::chrono::milliseconds(50));
  }
  std::this_thread::sleep_for(std::chrono::milliseconds(1000));
  if (!stopped) finish(2, "ERROR: writes were never stopped (trigger not established)");
  if (returned) finish(2, "ERROR: the write completed before shutdown (stall did not last; trigger not established)");
  printf("Writer is stalled; shutting the DB down ...\n");
  fflush(stdout);

  std::thread([] {
    std::this_thread::sleep_for(std::chrono::seconds(30));
    finish(1, "FAIL: Bug is present — the stalled write did not return within 30s after shutdown began");
  }).detach();

  ROCKSDB_NAMESPACE::CancelAllBackgroundWork(db, true);
  writer.join();
  printf("Stalled write returned: %s\n", write_status.ToString().c_str());
  s = db->Close();
  printf("Close() returned: %s\n", s.ToString().c_str());
  if (write_status.ok()) {
    finish(2, "ERROR: the stalled write succeeded, so the stall lifted on its own (inconclusive)");
  }
  finish(0, "PASS: Bug is fixed — the stalled write returned (" + write_status.ToString() + ") when the DB shut down");
}
