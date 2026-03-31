# FS29 Replay Validation Report

**Generated:** 20260330T233520Z
**Validator:** scripts/validate_fs29.sh
**Runs per case:** 3
**Setup timeout:** 1800s
**Reproduce timeout:** 600s

## Summary

| Result | Count |
|--------|-------|
| PASS (3/3 runs) | 23 |
| FLAKY (partial pass) | 0 |
| FAIL | 6 |
| SKIP (missing) | 0 |
| **Total FS29** | **29** |

## Per-Case Results

| Case | Setup | Run 1 | Run 2 | Run 3 | Overall | Setup Time | Notes |
|------|-------|-------|-------|-------|---------|------------|-------|
| bookkeeper-2614-recovery-fencing-gap | FAIL | SKIP | — | — | ❌ FAIL | 168s | exit 1 — [[1;31mERROR[m]   [1mmvn <args> -rf :bookkeeper-tools-framework[m |
| clickhouse-98079-keeper-addwatch | FAIL | SKIP | — | — | ❌ FAIL | 49s | exit 1 — ERROR: failed to build: failed to solve: process "/bin/sh -c apt-get update && apt-get install -y --no-install-recommend |
| consul-8377-snapshot-restore-index | FAIL | SKIP | — | — | ❌ FAIL | 224s | exit 2 — make: *** [GNUmakefile:156: dev-build] Error 1 |
| consul-9772-streaming-snapshot-cache | PASS | PASS | PASS | PASS | ✅ PASS | 14s | Bug reproduced deterministically: 3/3 runs confirmed |
| dragonfly-6687-replica-rdb-encoding | PASS | PASS | PASS | PASS | ✅ PASS | 159s | Bug reproduced deterministically: 3/3 runs confirmed |
| etcd-17158-delete-linearizability | PASS | PASS | PASS | PASS | ✅ PASS | 23s | Bug reproduced deterministically: 3/3 runs confirmed |
| etcd-17529-watch-compaction-loss | PASS | PASS | PASS | PASS | ✅ PASS | 23s | Bug reproduced deterministically: 3/3 runs confirmed |
| etcd-20221-watch-restore-revision | PASS | PASS | PASS | PASS | ✅ PASS | 35s | Bug reproduced deterministically: 3/3 runs confirmed |
| etcd-20893-force-new-cluster-learner | PASS | PASS | PASS | PASS | ✅ PASS | 52s | Bug reproduced deterministically: 3/3 runs confirmed |
| kvrocks-2214-slave-sync-gap | PASS | PASS | PASS | PASS | ✅ PASS | 52s | Bug reproduced deterministically: 3/3 runs confirmed |
| kvrocks-2520-namespace-fullsync | PASS | PASS | PASS | PASS | ✅ PASS | 207s | Bug reproduced deterministically: 3/3 runs confirmed |
| kvrocks-3208-replication-watermark | PASS | PASS | PASS | PASS | ✅ PASS | 55s | Bug reproduced deterministically: 3/3 runs confirmed |
| kvrocks-3356-replication-wal | FAIL | SKIP | — | — | ❌ FAIL | 4s | exit 1 — -- Configuring incomplete, errors occurred! |
| nats-6374-consumer-stuck-redelivery | PASS | PASS | PASS | PASS | ✅ PASS | 23s | Bug reproduced deterministically: 3/3 runs confirmed |
| nats-7308-delete-nonexistent-reset | PASS | PASS | PASS | PASS | ✅ PASS | 26s | Bug reproduced deterministically: 3/3 runs confirmed |
| nats-7718-subscription-leak | PASS | PASS | PASS | PASS | ✅ PASS | 30s | Bug reproduced deterministically: 3/3 runs confirmed |
| nats-7760-filter-stepdown | PASS | PASS | PASS | PASS | ✅ PASS | 29s | Bug reproduced deterministically: 3/3 runs confirmed |
| nats-7817-workqueue-message-loss | PASS | PASS | PASS | PASS | ✅ PASS | 30s | Bug reproduced deterministically: 3/3 runs confirmed |
| raft-268-shutdown-deadlock | PASS | FAIL | FAIL | FAIL | ❌ FAIL | 10s | Bug NOT reproduced in any of 3 runs |
| raft-358-negative-log-range | PASS | PASS | PASS | PASS | ✅ PASS | 2s | Bug reproduced deterministically: 3/3 runs confirmed |
| raft-460-logcache-store-order | PASS | PASS | PASS | PASS | ✅ PASS | 2s | Bug reproduced deterministically: 3/3 runs confirmed |
| raft-581-transfer-write-race | PASS | PASS | PASS | PASS | ✅ PASS | 2s | Bug reproduced deterministically: 3/3 runs confirmed |
| raft-609-prevote-contact-liveness | PASS | PASS | PASS | PASS | ✅ PASS | 2s | Bug reproduced deterministically: 3/3 runs confirmed |
| kafka-14334-delayed-fetch-purgatory | PASS | PASS | PASS | PASS | ✅ PASS | 358s | Bug reproduced deterministically: 3/3 runs confirmed |
| kafka-15170-endless-rebalance-loop | PASS | PASS | PASS | PASS | ✅ PASS | 52s | Bug reproduced deterministically: 3/3 runs confirmed |
| kafka-15784-txn-offset-atomicity | FAIL | SKIP | — | — | ❌ FAIL | 73s | exit 1 — BUILD FAILED in 1m 10s |
| zookeeper-4643-sync-epoch-ordering | PASS | PASS | PASS | PASS | ✅ PASS | 134s | Bug reproduced deterministically: 3/3 runs confirmed |
| zookeeper-4846-fuzzy-snapshot-acl | PASS | PASS | PASS | PASS | ✅ PASS | 93s | Bug reproduced deterministically: 3/3 runs confirmed |
| zookeeper-4925-diff-sync-committedlog-hole | PASS | PASS | PASS | PASS | ✅ PASS | 100s | Bug reproduced deterministically: 3/3 runs confirmed |

## Failure Details

### bookkeeper-2614-recovery-fencing-gap

**Overall:** FAIL
**Setup error:** exit 1 — [[1;31mERROR[m]   [1mmvn <args> -rf :bookkeeper-tools-framework[m

```
# setup.log (last 20 lines)
[[1;31mERROR[m]     unable to access file: java.nio.file.NoSuchFileException: /workspace/worktrees/bookkeeper-2614-recovery-fencing-gap/tools/framework/target/classes/org/apache/bookkeeper/tools/framework/CliSpec.class
[[1;31mERROR[m]     Please remove or make sure it appears in the correct subdirectory of the classpath.
[[1;31mERROR[m] /workspace/worktrees/bookkeeper-2614-recovery-fencing-gap/tools/framework/src/test/java/org/apache/bookkeeper/tools/framework/TestCli.java:[111,9] cannot access org.apache.bookkeeper.tools.framework.CliCommand
[[1;31mERROR[m]   bad class file: /workspace/worktrees/bookkeeper-2614-recovery-fencing-gap/tools/framework/target/classes/org/apache/bookkeeper/tools/framework/CliCommand.class
[[1;31mERROR[m]     unable to access file: java.nio.file.NoSuchFileException: /workspace/worktrees/bookkeeper-2614-recovery-fencing-gap/tools/framework/target/classes/org/apache/bookkeeper/tools/framework/CliCommand.class
[[1;31mERROR[m]     Please remove or make sure it appears in the correct subdirectory of the classpath.
[[1;31mERROR[m] /workspace/worktrees/bookkeeper-2614-recovery-fencing-gap/tools/framework/src/test/java/org/apache/bookkeeper/tools/framework/TestCli.java:[124,16] cannot access org.apache.bookkeeper.tools.framework.Cli
[[1;31mERROR[m]   bad class file: /workspace/worktrees/bookkeeper-2614-recovery-fencing-gap/tools/framework/target/classes/org/apache/bookkeeper/tools/framework/Cli.class
[[1;31mERROR[m]     unable to access file: java.nio.file.NoSuchFileException: /workspace/worktrees/bookkeeper-2614-recovery-fencing-gap/tools/framework/target/classes/org/apache/bookkeeper/tools/framework/Cli.class
[[1;31mERROR[m]     Please remove or make sure it appears in the correct subdirectory of the classpath.
[[1;31mERROR[m] -> [1m[Help 1][m
[[1;31mERROR[m] 
[[1;31mERROR[m] To see the full stack trace of the errors, re-run Maven with the [1m-e[m switch.
[[1;31mERROR[m] Re-run Maven using the [1m-X[m switch to enable full debug logging.
[[1;31mERROR[m] 
[[1;31mERROR[m] For more information about the errors and possible solutions, please read the following articles:
[[1;31mERROR[m] [1m[Help 1][m http://cwiki.apache.org/confluence/display/MAVEN/MojoFailureException
[[1;31mERROR[m] 
[[1;31mERROR[m] After correcting the problems, you can resume the build with the command
[[1;31mERROR[m]   [1mmvn <args> -rf :bookkeeper-tools-framework[m
```

### clickhouse-98079-keeper-addwatch

**Overall:** FAIL
**Setup error:** exit 1 — ERROR: failed to build: failed to solve: process "/bin/sh -c apt-get update && apt-get install -y --no-install-recommend

```
# setup.log (last 20 lines)
8.608 Hit:4 http://archive.ubuntu.com/ubuntu noble InRelease
8.745 Hit:5 http://archive.ubuntu.com/ubuntu noble-updates InRelease
8.883 Hit:6 http://archive.ubuntu.com/ubuntu noble-backports InRelease

10.05 E: The repository 'http://apt.llvm.org/noble llvm-toolchain-noble-23 Release' does not have a Release file.
------
clickhouse.Dockerfile:4
--------------------
   3 |     # Install clang-23 from LLVM versioned repo (pinned to clang-23 channel)
   4 | >>> RUN apt-get update && apt-get install -y --no-install-recommends lsb-release && \
   5 | >>>     wget -qO- https://apt.llvm.org/llvm-snapshot.gpg.key | tee /etc/apt/trusted.gpg.d/apt.llvm.org.asc >/dev/null && \
   6 | >>>     echo "deb http://apt.llvm.org/$(lsb_release -cs)/ llvm-toolchain-$(lsb_release -cs)-23 main" \
   7 | >>>         > /etc/apt/sources.list.d/llvm.list && \
   8 | >>>     apt-get update && apt-get install -y --no-install-recommends \
   9 | >>>         clang-23 lld-23 \
  10 | >>>         default-jre-headless \
  11 | >>>     && rm -rf /var/lib/apt/lists/*
  12 |     
--------------------
ERROR: failed to build: failed to solve: process "/bin/sh -c apt-get update && apt-get install -y --no-install-recommends lsb-release &&     wget -qO- https://apt.llvm.org/llvm-snapshot.gpg.key | tee /etc/apt/trusted.gpg.d/apt.llvm.org.asc >/dev/null &&     echo \"deb http://apt.llvm.org/$(lsb_release -cs)/ llvm-toolchain-$(lsb_release -cs)-23 main\"         > /etc/apt/sources.list.d/llvm.list &&     apt-get update && apt-get install -y --no-install-recommends         clang-23 lld-23         default-jre-headless     && rm -rf /var/lib/apt/lists/*" did not complete successfully: exit code: 100
```

### consul-8377-snapshot-restore-index

**Overall:** FAIL
**Setup error:** exit 2 — make: *** [GNUmakefile:156: dev-build] Error 1

```
# setup.log (last 20 lines)
go: downloading k8s.io/utils v0.0.0-20190801114015-581e00157fb1
go: downloading github.com/googleapis/gnostic v0.2.0
go: downloading github.com/spf13/pflag v1.0.5
go: downloading github.com/json-iterator/go v1.1.9
go: downloading github.com/modern-go/reflect2 v1.0.1
go: downloading sigs.k8s.io/yaml v1.1.0
go: downloading github.com/modern-go/concurrent v0.0.0-20180306012644-bacd9c7ef1dd
go: downloading github.com/sirupsen/logrus v1.4.2
go: downloading github.com/googleapis/gax-go/v2 v2.0.5
go: downloading go.opencensus.io v0.22.0
go: downloading github.com/jmespath/go-jmespath v0.0.0-20180206201540-c2b33e8439af
go: downloading github.com/Azure/go-autorest/autorest/validation v0.2.0
go: downloading github.com/Azure/go-autorest/autorest/to v0.3.0
cp: cannot create regular file 'pkg.bin.new/linux_amd64/consul': No such file or directory
tput: No value for $TERM and no -T specified
tput: No value for $TERM and no -T specified
ERROR: Failed to build Consul for linux/amd64
tput: No value for $TERM and no -T specified
rm: cannot remove 'pkg.bin.new': No such file or directory
make: *** [GNUmakefile:156: dev-build] Error 1
```

### kvrocks-3356-replication-wal

**Overall:** FAIL
**Setup error:** exit 1 — -- Configuring incomplete, errors occurred!

```
# setup.log (last 20 lines)
  Extract of
  '/workspace/worktrees/kvrocks-3356-replication-wal/build/_deps/pegtl-subbuild/pegtl-populate-prefix/src/3.2.8.zip'
  failed


gmake[2]: *** [CMakeFiles/pegtl-populate.dir/build.make:102: pegtl-populate-prefix/src/pegtl-populate-stamp/pegtl-populate-download] Error 1
gmake[1]: *** [CMakeFiles/Makefile2:83: CMakeFiles/pegtl-populate.dir/all] Error 2
gmake: *** [Makefile:91: all] Error 2

CMake Error at /usr/share/cmake-3.28/Modules/FetchContent.cmake:1679 (message):
  Build step for pegtl failed: 2
Call Stack (most recent call first):
  /usr/share/cmake-3.28/Modules/FetchContent.cmake:1819:EVAL:2 (__FetchContent_directPopulate)
  /usr/share/cmake-3.28/Modules/FetchContent.cmake:1819 (cmake_language)
  cmake/utils.cmake:31 (FetchContent_Populate)
  cmake/pegtl.cmake:27 (FetchContent_MakeAvailableWithArgs)
  CMakeLists.txt:193 (include)


-- Configuring incomplete, errors occurred!
```

### raft-268-shutdown-deadlock

**Overall:** FAIL
**Notes:** Bug NOT reproduced in any of 3 runs

```
# reproduce-run1.log (last 20 lines)
Attempt 33: OK
Attempt 34: OK
Attempt 35: OK
Attempt 36: OK
Attempt 37: OK
Attempt 38: OK
Attempt 39: OK
Attempt 40: OK
Attempt 41: OK
Attempt 42: OK
Attempt 43: OK
Attempt 44: OK
Attempt 45: OK
Attempt 46: OK
Attempt 47: OK
Attempt 48: OK
Attempt 49: OK
Attempt 50: OK

PASS: Bug is fixed — all 50 runs completed without deadlock
```

### kafka-15784-txn-offset-atomicity

**Overall:** FAIL
**Setup error:** exit 1 — BUILD FAILED in 1m 10s

```
# setup.log (last 20 lines)

FAILURE: Build failed with an exception.

* What went wrong:
Could not create an instance of type org.gradle.api.internal.initialization.DefaultScriptHandler.
> Could not create service of type ChecksumService using BuildSessionScopeServices.createChecksumService().
   > Timeout waiting to lock checksums cache (/workspace/worktrees/kafka-15784-txn-offset-atomicity/.gradle/8.5/checksums). It is currently in use by another Gradle instance.
     Owner PID: 47
     Our PID: 44
     Owner Operation: 
     Our operation: 
     Lock file: /workspace/worktrees/kafka-15784-txn-offset-atomicity/.gradle/8.5/checksums/checksums.lock

* Try:
> Run with --stacktrace option to get the stack trace.
> Run with --info or --debug option to get more log output.
> Run with --scan to get full insights.
> Get more help at https://help.gradle.org.

BUILD FAILED in 1m 10s
```


## Log Files

Full logs: `validation-logs/20260330T233520Z/`

Per-case: `validation-logs/20260330T233520Z/<case-name>/`
