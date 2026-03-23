# Distributed Systems Bug Benchmark Suite

A benchmark suite of real-world bugs from open-source distributed systems, each with automated scripts to reproduce the bug from source. Designed for evaluating debugging tools, program analysis techniques, and automated repair systems.

## Quick Start

Pick a case, set up the codebase, and reproduce the bug:

```bash
cd cases/dragonfly-6753-populate-sigfpe/
./setup.sh       # clone repo, checkout buggy commit, build (~10 min)
./reproduce.sh   # trigger the bug, prints FAIL (bug present) or PASS (bug fixed)
```

The workspace defaults to `$HOME/bug-bench/<case-name>/`. Override with:

```bash
export BENCH_WORKSPACE=/your/path
```

## What's in a Case

Each case folder contains:

```
cases/<project>-<issue#>-<slug>/
├── README.md        # Quick start, prerequisites, what to expect
├── setup.sh         # Automated: clone, checkout buggy commit, install deps, build
├── reproduce.sh     # Automated: start system, trigger bug, report PASS/FAIL
├── symptom.md       # Observable behavior and error messages
├── setup.md         # Detailed setup documentation
├── reproduce.md     # Step-by-step reproduction procedure
└── verification.md  # Pass/fail verification criteria
```

- `setup.sh` and `reproduce.sh` are the executable entry points — everything else is documentation.
- `reproduce.sh` exits with code 1 and prints `FAIL` when the bug is present, code 0 and `PASS` when the bug is fixed.
- Solutions are in `cases-solution/<case-name>/solution.md` — consult only after attempting diagnosis.

## Verified Cases (31)

All cases build from source on Ubuntu 24.04 and reliably reproduce the described bug.

| Project | Language | Cases | Bug Types |
|---------|----------|-------|-----------|
| Dragonfly | C++ | 14 | Crashes (SIGABRT, SIGFPE), replication failure, pipeline stall |
| NATS Server | Go | 5 | Subscription leak, message loss, filter bugs, perf regression |
| Kvrocks | C++ | 4 | Crash, data loss, protocol violation, unbounded WAL growth |
| etcd | Go | 3 | Data race, linearizability violation, stale cluster state |
| Raft (hashicorp) | Go | 2 | Shutdown deadlock, invalid log compaction range |
| ClickHouse | C++ | 1 | Keeper disconnects client on addWatch |
| RocksDB | C++ | 1 | DB::Close() hangs with stalled writes |
| Seastar | C++ | 1 | Cross-shard realloc assertion crash |

See [`index.md`](index.md) for the full list with links and descriptions.

## Repository Structure

```
.
├── README.md                          # This file
├── index.md                           # Master index of all 31 verified cases
├── reproduction_results.md            # Detailed reproduction evidence
├── cases/                             # Bug cases (problem only, no solution)
│   ├── dragonfly-6753-populate-sigfpe/
│   ├── etcd-19172-embed-data-race/
│   ├── nats-7760-filter-stepdown/
│   └── ...                            # 31 cases with scripts, 29 more as documentation
├── cases-solution/                    # Solutions (root cause + fix)
│   ├── dragonfly-6753-populate-sigfpe/
│   │   └── solution.md
│   └── ...
├── distributed_bugs_report.md         # Reference: 105 bugs across 20 Go/Rust/C projects
├── cpp_distributed_bugs_supplement.md # Reference: 35 C++ bugs across 5 projects
├── bug_verification_oracles.md        # Reference: pass/fail oracles for all 60 cases
├── top60_ranked_bugs.md               # Reference: ranking methodology
└── CLAUDE.md                          # AI assistant instructions
```

## Prerequisites

- **Ubuntu 24.04** (tested) or compatible Linux
- **Git** 2.40+
- **Build tools**: `build-essential`, `cmake`, `ninja-build` (installed automatically by `setup.sh`)
- **Go 1.22+** for Go-based cases (etcd, NATS, Raft)
- **Clang 23** for ClickHouse (installed automatically by `setup.sh` from LLVM nightly)
- **sudo access** for `apt-get install` (dependency installation) and `iptables` (one Kvrocks case)

Each `setup.sh` installs its own dependencies via `apt-get`. No Docker required.

## Bug Categories

The cases cover these distributed systems failure modes:

- **Crashes**: SIGABRT, SIGFPE, SIGSEGV from assertion failures, division by zero, out-of-bounds access
- **Deadlocks**: Shutdown/snapshot race conditions
- **Data loss**: Silent deletion, message loss, stale cache
- **Protocol violations**: Double responses, incompatible API behavior
- **Performance regressions**: Pipeline stalls, unbounded resource growth
- **Linearizability violations**: Cache returning stale data

## Intended Use

1. **Debugger evaluation**: Can your tool diagnose the root cause from the symptom?
2. **Automated repair**: Can your system generate a correct fix?
3. **Program analysis**: Can your tool detect the bug pattern statically?
4. **Education**: Real-world examples of distributed systems failure modes.

The `cases/` directory contains the problem only. The `cases-solution/` directory contains the answer. Use them separately to avoid leaking solutions during evaluation.
