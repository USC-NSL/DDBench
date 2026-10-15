# Evaluation harness

Scripts for running an AI agent on DDBench cases and scoring the results. They
drive `../bench.sh` and need only Docker, bash and Python 3.8+ (standard
library).

| Script | Purpose |
|--------|---------|
| `run_agent.sh` | Batch runner for mini-swe-agent. For each case it runs setup, reset, the agent (with a timeout), scoring, and a final reset. |
| `score_case.sh` | Scores one case after an agent edited its worktree: extracts the patch, analyzes the trajectory, runs `bench.sh reproduce`, writes `result.json`, and resets. |
| `score_surface.sh` | Runs `score_case.sh` over every case of a tier, then aggregates. |
| `extract_patch.sh` | Writes a replayable `patch.diff` (and metadata) from a case worktree. |
| `aggregate_results.py` | Builds `summary.json` / `summary.md` from `<results>/<case>/result.json`. |
| `analyze_trajectory.py` | Extracts step, cost, token and behaviour metrics from a mini-swe-agent trajectory. |
| `eval_all.py` | Backend of `bench.sh eval-all` (parallel patch evaluation). |
| `configs/` | mini-swe-agent configs; see [`configs/README.md`](configs/README.md). |

## Verdicts

`bench.sh reproduce` exits 0 = PASS (bug fixed), 1 = FAIL (bug still present, or
the worktree does not build), or 2 = ERROR (the oracle or the infrastructure
could not decide). The harness records `result`/`verdict` as PASS, FAIL or
ERROR.

- ERROR results are reported separately and are not counted as model failures.
  The headline `pass_rate` is passed / (passed + failed). `pass_rate_all` =
  passed / total counts ERROR as not passed. Re-run ERROR cases.
- An oracle run that exceeds its timeout counts as FAIL
  (`failure_reason: timeout`).
- When the agent itself hits `run_agent.sh --timeout`, the case is recorded as
  FAIL (`agent_timeout`) without running the oracle.

## Results layout

The default results directory is `results/` in the repository root (it is
gitignored). Change it with `--results-dir` or with `DDBENCH_RESULTS_DIR`.

```
results/mini-swe-agent/<model>/<timestamp>/
├── run_metadata.json
├── summary.json, summary.md          # aggregate_results.py
├── <case>_setup.log, <case>_prereset.log, <case>_agent.log
└── <case>/
    ├── trajectory.traj.json          # mini-swe-agent trajectory
    ├── trajectory_analysis.json
    ├── patch.diff                    # replay with: bench.sh eval <case> --patch patch.diff
    ├── patch_stat.txt, patch_numstat.txt, patch_metadata.json
    ├── reproduce_stdout.log, reproduce_stderr.log
    └── result.json
```

### `result.json` (score_case.sh)

```json
{
  "case": "raft-358-negative-log-range",
  "result": "PASS",            // PASS | FAIL | ERROR
  "verdict": "PASS",           // same value (the key bench.sh eval uses)
  "exit_code": 0,              // bench.sh reproduce exit code (124/137 = timeout)
  "duration_seconds": 41,
  "summary": "PASS: Bug is fixed — ...",
  "scored_at": "2026-10-14T12:00:00+00:00",
  "failure_reason": "test_failure",   // FAIL/ERROR only: test_failure | build_failure |
                                      //   timeout | agent_timeout | oracle_error
  "agent_timeout": true,              // only when the agent hit its timeout
  "patch_metadata": { "base_commit": "...", "files_changed": 1, "lines_added": 5,
                      "lines_removed": 0, "patch_category": "surgical",
                      "changed_files": [...], "skipped_files": [...] },
  "steps_used": 37, "exit_status": "Submitted", "cost": 0.84,
  "tokens": {...}, "timing": {...}, "behavior": {...}   // from the trajectory, if any
}
```

## Patch extraction

`extract_patch.sh <case> <out-dir>` diffs the worktree against the buggy
commit through a temporary git index, so the worktree, its index and its refs
are left alone. The diff includes:

- new untracked files;
- deletions and mode changes;
- commits the agent made on top of the buggy commit;
- edits inside submodules (written as paths under the submodule directory).

It leaves out `SYMPTOM.md`, `REBUILD.sh`, `context/`, gitignored build
outputs, and new files larger than 1 MiB (`DDBENCH_MAX_NEW_FILE`; skipped
files are listed in `patch_metadata.json`). Because of this, `patch.diff`
replays with `bench.sh eval` on a fresh setup.

## Patch evaluation without an agent

See `./bench.sh help`:

```bash
./bench.sh eval <case> --patch fix.diff --runs 3 --json result.json
./bench.sh eval-all --predictions preds.jsonl --out results/my-run --jobs 4
```
