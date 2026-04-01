# FS28 Replay Validation Report

**Generated:** 20260331T045200Z
**Validator:** bench.sh setup + bench.sh reproduce (clean Docker volumes)
**Total FS28 cases:** 28 (clickhouse-98079-keeper-addwatch removed from corpus)

## Summary

| Result | Count |
|--------|-------|
| PASS (bug confirmed) | 28 |
| FLAKY (partial pass) | 0 |
| FAIL | 0 |
| SKIP (missing) | 0 |
| **Total FS28** | **28** |

## Per-Case Results

| Case | Setup | Reproduce | Notes |
|------|-------|-----------|-------|
| bookkeeper-2614-recovery-fencing-gap | ✅ PASS | ✅ bug confirmed | Fixed: added `mvn clean` + persistent Maven cache |
| consul-8377-snapshot-restore-index | ✅ PASS | ✅ bug confirmed | Fixed: added `mkdir -p pkg.bin.new/linux_amd64` |
| consul-9772-streaming-snapshot-cache | ✅ PASS | ✅ bug confirmed | No changes needed |
| dragonfly-6687-replica-rdb-encoding | ✅ PASS | ✅ bug confirmed | No changes needed |
| etcd-17158-delete-linearizability | ✅ PASS | ✅ bug confirmed | No changes needed |
| etcd-17529-watch-compaction-loss | ✅ PASS | ✅ bug confirmed | No changes needed |
| etcd-20221-watch-restore-revision | ✅ PASS | ✅ bug confirmed | No changes needed |
| etcd-20893-force-new-cluster-learner | ✅ PASS | ✅ bug confirmed | No changes needed |
| kafka-14334-delayed-fetch-purgatory | ✅ PASS | ✅ bug confirmed | Fixed: added `--no-daemon` to Gradle |
| kafka-15170-endless-rebalance-loop | ✅ PASS | ✅ bug confirmed | Fixed: added `--no-daemon` to Gradle |
| kafka-15784-txn-offset-atomicity | ✅ PASS | ✅ bug confirmed | Fixed: added `--no-daemon` to Gradle |
| kvrocks-2214-slave-sync-gap | ✅ PASS | ✅ bug confirmed | No changes needed |
| kvrocks-2520-namespace-fullsync | ✅ PASS | ✅ bug confirmed | Fixed: explicit `CMAKE_CXX_COMPILER=g++` |
| kvrocks-3208-replication-watermark | ✅ PASS | ✅ bug confirmed | No changes needed |
| kvrocks-3356-replication-wal | ✅ PASS | ✅ bug confirmed | Fixed: locales + `LANG=en_US.UTF-8` in Dockerfile |
| nats-6374-consumer-stuck-redelivery | ✅ PASS | ✅ bug confirmed | No changes needed |
| nats-7308-delete-nonexistent-reset | ✅ PASS | ✅ bug confirmed | No changes needed |
| nats-7718-subscription-leak | ✅ PASS | ✅ bug confirmed | No changes needed |
| nats-7760-filter-stepdown | ✅ PASS | ✅ bug confirmed | No changes needed |
| nats-7817-workqueue-message-loss | ✅ PASS | ✅ bug confirmed | No changes needed |
| raft-268-shutdown-deadlock | ✅ PASS | ✅ bug confirmed | Fixed: rewrote test harness with aggressive timing |
| raft-358-negative-log-range | ✅ PASS | ✅ bug confirmed | No changes needed |
| raft-460-logcache-store-order | ✅ PASS | ✅ bug confirmed | No changes needed |
| raft-581-transfer-write-race | ✅ PASS | ✅ bug confirmed | No changes needed |
| raft-609-prevote-contact-liveness | ✅ PASS | ✅ bug confirmed | No changes needed |
| zookeeper-4643-sync-epoch-ordering | ✅ PASS | ✅ bug confirmed | Fixed: `build-essential` in Dockerfile + persistent Maven cache |
| zookeeper-4846-fuzzy-snapshot-acl | ✅ PASS | ✅ bug confirmed | Persistent Maven cache added |
| zookeeper-4925-diff-sync-committedlog-hole | ✅ PASS | ✅ bug confirmed | Persistent Maven cache added |

## Removed Cases

### clickhouse-98079-keeper-addwatch

**Removed from corpus on 20260331.** The ClickHouse Docker image could not be built due to an
unavailable LLVM apt repository (`llvm-toolchain-noble-23`). The case required clang-23 which
is not available in any stable repository. All references removed from:
- `cases/clickhouse-98079-keeper-addwatch/` (case directory)
- `cases-solution/clickhouse-98079-keeper-addwatch/` (solution directory)
- `docker/clickhouse.Dockerfile`
- `registry/fs28_membership.json` (29→28)
- `registry/fs42_membership.json` (43→42)
- `registry/fs55_membership.json` (56→55)
- `registry/case_registry.json` (62→61)

## Fixes Applied

### Infrastructure Fixes (Dockerfiles)

| Fix | Cases | Root Cause |
|-----|-------|-----------|
| Added `locales` package + `LANG=en_US.UTF-8` | kvrocks-3356 | CMake FetchContent cannot extract zip files with UTF-8 paths |
| Added `build-essential` package | zookeeper-4643 | Maven jute codegen requires gcc for native compilation |

### Build Fixes (case.yaml)

| Fix | Cases | Root Cause |
|-----|-------|-----------|
| `--no-daemon` added to `./gradlew` | kafka-14334, kafka-15170, kafka-15784 | Gradle daemon lock file collision during incremental Docker builds |
| `mvn clean` added to build command | bookkeeper-2614 | Stale `.class` files from prior builds cause `NoSuchFileException` |
| `mkdir -p pkg.bin.new/linux_amd64` before `make dev-build` | consul-8377 | Makefile `cp` target directory does not exist |
| `-DCMAKE_CXX_COMPILER=g++` added to cmake args | kvrocks-2520 | FetchContent sub-project needs explicit C++ compiler |
| `-Dmaven.repo.local=/workspace/.m2` | bookkeeper-2614, zookeeper-4643/4846/4925 | Persist Maven local repo across Docker containers |

### Reproduce Fixes

| Fix | Cases | Root Cause |
|-----|-------|-----------|
| Rewrote `test_main.go` with `GOMAXPROCS(1)`, `SnapshotThreshold=1`, `SnapshotInterval=10ms`, 200ms FSM.Snapshot(), fast election timeouts, `io.Discard` logging | raft-268 | Deadlock race window too narrow with default parameters; now triggers within 1–3 attempts |
| Simplified `reproduce.sh` to single binary invocation (internal 50-attempt loop) | raft-268 | Avoids process restart overhead per attempt |

## Validation Methodology

All cases validated from completely clean Docker volumes:
1. `docker volume rm bug-bench-<project>-src` (remove any cached state)
2. `./bench.sh setup <case>` (clone repo, checkout buggy commit, build)
3. `./bench.sh reproduce <case>` (run test oracle, confirm bug is present)

Exit codes: `exit 1` = PASS (bug confirmed), `exit 0` = FAIL (bug not triggered), `exit 124` = TIMEOUT.

## Log Files

- Initial validation: `validation-logs/20260330T233520Z/`
- Revalidation (fixed cases): `validation-logs/revalidation-20260331T025429Z/`
- Final clean validation: `validation-logs/final-check-20260331T042252Z/`
