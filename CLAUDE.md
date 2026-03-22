# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A curated collection of 60+ real-world bug cases from open-source distributed database and infrastructure projects, designed for evaluating distributed interactive debuggers. Each case documents a confirmed bug with reproduction steps and a known solution.

## Repository structure

- `cases/<project>-<issue#>-<slug>/` — Bug case files (the problem description, no solution)
  - `symptom.md` — Observable behavior and error messages
  - `setup.md` — Repository, language, issue/PR links, clone instructions, build commands
  - `reproduce.md` — Step-by-step reproduction procedure
  - `verification.md` — Pass/fail test to confirm if the bug is present or fixed
- `cases-solution/<project>-<issue#>-<slug>/` — Corresponding solution files
  - `solution.md` — Root cause analysis, fix description, fix commit, and how to apply
- `distributed_bugs_report.md` — Master report covering 105 bugs across 20 Go/Rust/C projects (etcd, TiKV, CockroachDB, NATS, Raft, Nomad, etc.)
- `cpp_distributed_bugs_supplement.md` — Supplement report covering 35 C++ bugs across 5 projects (ScyllaDB, ClickHouse, Dragonfly, Seastar, Redpanda/Kvrocks/RocksDB)

## Covered projects

Cases span these distributed systems (naming convention: `<project>-<issue#>`):

| Project | Language | Cases |
|---------|----------|-------|
| ClickHouse | C++ | 9 |
| Dragonfly | C++ | 14 |
| etcd | Go | 7 |
| Kvrocks | C++ | 4 |
| NATS Server | Go | 6 |
| Raft (hashicorp) | Go | 4 |
| Redpanda | C++ | 3 |
| RocksDB | C++ | 2 |
| ScyllaDB | C++ | 6 |
| CockroachDB | Go | 1 |
| Nomad | Go | 1 |
| Seastar | C++ | 1 |

## Working with cases

- The `cases/` directory contains the problem only — use these when evaluating a debugger's ability to diagnose without hints.
- The `cases-solution/` directory contains the answer — consult only for verification or after an attempt.
- Each case's `setup.md` has the exact git checkout command (typically `<fix-commit>~1` for the buggy version) and build instructions specific to that project.
- Bug categories include: race conditions, deadlocks, data loss, crashes (segfault/SIGFPE/OOB), linearizability violations, replication errors, upgrade/migration failures, and performance regressions.

## No build/test commands

This is a documentation-only repository with no code to build, lint, or test. There are no dependencies or CI pipelines.
