# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A benchmark suite of 31 verified real-world bug cases from open-source distributed systems. Each case has automated scripts (`setup.sh` + `reproduce.sh`) that build from source on Ubuntu 24.04 and reliably reproduce the bug.

## Repository structure

- `cases/<project>-<issue#>-<slug>/` — Bug case files
  - `README.md` — Quick start guide
  - `setup.sh` — Clone, checkout buggy commit, install deps, build (executable)
  - `reproduce.sh` — Trigger bug, report PASS/FAIL (executable)
  - `symptom.md` — Observable behavior and error messages
  - `setup.md` — Detailed setup documentation
  - `reproduce.md` — Step-by-step reproduction procedure
  - `verification.md` — Pass/fail verification criteria
- `cases-solution/<project>-<issue#>-<slug>/solution.md` — Root cause + fix (do not consult during evaluation)
- `index.md` — Master index of all 31 verified cases
- `reproduction_results.md` — Detailed reproduction evidence

## Working with cases

```bash
cd cases/<case-name>/
./setup.sh       # one-time: clone, build (~5-90 min depending on project)
./reproduce.sh   # reproduce bug, prints FAIL (present) or PASS (fixed)
```

- Workspace defaults to `$HOME/bug-bench/`, override with `BENCH_WORKSPACE=/path`
- All builds are from source, no Docker
- Each `setup.sh` installs its own dependencies via `apt-get`

## Covered projects (31 verified cases)

| Project | Language | Cases |
|---------|----------|-------|
| Dragonfly | C++ | 14 |
| NATS Server | Go | 5 |
| Kvrocks | C++ | 4 |
| etcd | Go | 3 |
| Raft (hashicorp) | Go | 2 |
| ClickHouse | C++ | 1 |
| RocksDB | C++ | 1 |
| Seastar | C++ | 1 |

## No build/test commands for this repo itself

This is a benchmark suite — there's no code to build or test at the repo level. Each case is self-contained with its own build system.
