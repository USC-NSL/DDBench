# /mine-batch — Batch Case Mining

Process multiple bug candidates through `/mine` sequentially and produce an aggregate report. Useful for scaling the benchmark when you have a pre-screened list of candidates.

## Usage

```
/mine-batch <candidates-file>
/mine-batch <candidates-file> --dry-run
/mine-batch <url1> <url2> <url3> ...
```

**Examples:**
```
# From a candidates file
/mine-batch candidates.md

# Inline URLs
/mine-batch https://github.com/etcd-io/etcd/pull/20281 https://github.com/nats-io/nats-server/pull/7708

# Dry run — evaluate all candidates without creating cases
/mine-batch candidates.md --dry-run
```

## Candidates file format

A markdown file with one candidate per line. Each line is a URL (PR or issue) optionally followed by `-- <notes>`.

```markdown
# Candidates for batch mining
# Lines starting with # are comments. Blank lines are skipped.

https://github.com/etcd-io/etcd/pull/20281 -- watch restore future revision bug
https://github.com/apache/kvrocks/issues/2520
https://github.com/nats-io/nats-server/pull/7708 -- WQ consumer map crash
https://github.com/hashicorp/raft/pull/581 -- transfer write race
```

## Procedure

### Step 1: Parse candidate list

- If file path: read file, extract URLs (one per line, skip `#` comments and blanks)
- If inline URLs: use them directly
- Validate each URL is a GitHub PR or issue URL
- Check deduplication against existing cases: `ls cases/ | grep <issue-number>`
- Report: `Found N candidates (M already in benchmark, skipping)`

### Step 2: Process sequentially

For each candidate, run `/mine <url>`:

```
for candidate in candidates:
    if already in benchmark → skip
    run /mine <url>
    record result: COMPLETE | EVAL_REJECT | SETUP_FAIL | REPRO_FAIL | ORACLE_FAIL
    if COMPLETE → increment success count
    continue to next candidate (do NOT abort on failure)
```

**Resource management:**
- Run cases sequentially (Docker builds are resource-heavy)
- After each case completes or fails, clean up Docker state if needed
- Log progress: `[3/10] Mining nats-7707-wq-consumer-map-crash...`

### Step 3: Aggregate report

```
=== Batch Mining Report ===
Date: <date>
Candidates: N

| # | URL | Case Name | Status | Notes |
|---|-----|-----------|--------|-------|
| 1 | etcd/pull/20281 | etcd-20221-watch-restore-revision | COMPLETE | Verified + oracle sound |
| 2 | kvrocks/issues/2520 | kvrocks-2520-namespace-fullsync | COMPLETE | Verified + oracle sound |
| 3 | nats/pull/7708 | — | EVAL_REJECT | Fix spans 8 files (criterion #6) |
| 4 | raft/pull/581 | raft-581-transfer-write-race | SETUP_FAIL | Build timeout after 3 attempts |

Summary:
  COMPLETE:     2 cases added to benchmark
  EVAL_REJECT:  1 (failed selection criteria)
  SETUP_FAIL:   1 (build issues — manual review needed)
  REPRO_FAIL:   0
  ORACLE_FAIL:  0
  SKIPPED:      0 (already in benchmark)
```

### Step 4: Triage failures

For each non-COMPLETE case, output:
- The phase where it failed (evaluation, setup, reproduce, oracle)
- The `/diagnose-case` classification if applicable
- Last 10 lines of error output
- Suggested next step

## Status definitions

| Status | Meaning |
|--------|---------|
| COMPLETE | All phases passed — case added to benchmark |
| EVAL_REJECT | Failed mandatory selection criteria in Phase 2 |
| SETUP_FAIL | `bench.sh setup` failed after 3 `/diagnose-case` attempts |
| REPRO_FAIL | Reproduce script failed after 3 `/diagnose-case` attempts |
| ORACLE_FAIL | Oracle unsound after 3 `/diagnose-case` attempts |
| SKIPPED | Issue already exists in benchmark |

## Notes

- Never abort the batch on a single failure — log it and continue
- Each `/mine` invocation is independent; a failure in one case does not affect others
- For large batches (10+), consider running in a `tmux` session to avoid timeout
- The candidates file can be iteratively refined: remove COMPLETE cases, add new ones, re-run
- Use `--dry-run` first to evaluate all candidates before committing to full builds

## References

- `/mine` — single-case mining pipeline (this skill wraps it)
- `/verify-cases` — can verify all new cases at once after batch completes
- `/verify-oracle` — can verify all oracles at once after batch completes
