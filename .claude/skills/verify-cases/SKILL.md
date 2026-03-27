# /verify-cases — Batch Case Verification

Run `bench.sh setup` and `bench.sh reproduce` across all (or specified) cases and produce an aggregate report.

## Usage

```
/verify-cases                     # verify all cases
/verify-cases <case1> <case2>     # verify specific cases
/verify-cases --project dragonfly # verify all cases for a project
```

## Procedure

### Step 1: Determine case list

- No arguments: list all directories in `cases/` as the case set
- Specific cases: use the provided names
- `--project <name>`: filter to cases starting with `<project>-`

Validate each case directory exists and contains `case.yaml`.

### Step 2: Run verification (sequentially to avoid resource contention)

For each case, run the following and capture output + exit code:

```bash
# Setup phase
./bench.sh setup <case-name> 2>&1
SETUP_EXIT=$?

# Reproduce phase (only if setup succeeded)
if [ $SETUP_EXIT -eq 0 ]; then
    ./bench.sh reproduce <case-name> 2>&1
    REPRO_EXIT=$?
fi
```

**Important resource management rules:**
- Run cases sequentially (NOT in parallel) to avoid Docker resource contention
- Set a timeout of 30 minutes for setup (builds can be slow) and 5 minutes for reproduce
- If setup fails, mark case as SETUP_FAIL and move to the next case
- Capture the last 20 lines of output for the report

### Step 3: Classify results

For each case, determine the status:

| Status | Condition |
|--------|-----------|
| VERIFIED | Setup OK + reproduce exits 1 with "FAIL:" in output (bug present, as expected) |
| FIXED | Setup OK + reproduce exits 0 with "PASS:" in output (bug already fixed — wrong commit?) |
| SETUP_FAIL | Setup exited non-zero |
| REPRO_ERROR | Reproduce exited non-zero but without "FAIL:" in output (script error, not bug detection) |
| TIMEOUT | Setup or reproduce exceeded timeout |

### Step 4: Generate report

Output a markdown table:

```
=== Verification Report ===
Date: <date>
Cases tested: N

| Case | Project | Setup | Reproduce | Status | Notes |
|------|---------|-------|-----------|--------|-------|
| dragonfly-6614-monitor-multiexec | dragonfly | OK (45s) | FAIL (3s) | VERIFIED | Bug present as expected |
| etcd-19172-embed-data-race | etcd | OK (120s) | FAIL (15s) | VERIFIED | Bug present as expected |
| ... | ... | ... | ... | ... | ... |

Summary:
  VERIFIED:    N cases (bug present on buggy commit)
  FIXED:       N cases (UNEXPECTED — check buggy_commit)
  SETUP_FAIL:  N cases (build issues)
  REPRO_ERROR: N cases (script bugs)
  TIMEOUT:     N cases (resource issues)
```

### Step 5: Triage failures

For each non-VERIFIED case, output:
- The last 20 lines of setup/reproduce output
- A suggested next step (e.g., "check build dependencies", "verify buggy_commit resolves correctly", "increase timeout")

### Notes

- A VERIFIED result means the oracle fires correctly on the buggy commit. It does NOT confirm oracle soundness in the other direction (PASS on fix). Use `/verify-oracle` for that.
- If many cases from the same project fail setup, the project Dockerfile likely needs updating.
- Resource contention (parallel Docker builds sharing CPU/memory) was a major friction source in past sessions — always run sequentially.
