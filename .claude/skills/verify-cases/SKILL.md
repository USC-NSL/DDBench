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

### Step 1.5: Static oracle quality scan (pre-flight)

Before running any cases, scan each `reproduce.sh` for anti-patterns that make the oracle fragile or fix-specific. Flag (but don't block) cases that match:

| Anti-pattern | Grep pattern | Why it's bad |
|---|---|---|
| FIX_COMMIT dependency | `FIX_COMMIT=` | Test code extracted from a specific fix commit won't work with alternative fixes |
| `git show` from fix | `git show.*FIX_COMMIT\|git show.*:.*test` | Same: test is coupled to upstream fix |
| `git checkout` from fix | `git checkout.*FIX_COMMIT\|git checkout "\$FIX` | Pulls fix-commit files into working tree |
| Reflection field check | `getDeclaredField\|getDeclaredMethod` used as the PASS/FAIL assertion | Checks code structure, not behavior |
| Source grep as oracle | `grep -q.*"\(source file\)"` used to branch PASS/FAIL | Detects fix text, not fix effect |
| `sed -i` on production code | `sed -i.*src/main` | Injects accessors into production code to expose internal state |
| `sudo` in reproduce.sh | `sudo ` | The images ship no `sudo` (and `bench.sh reproduce` already runs as root). The step silently fails and the trigger never happens |
| Swallowed trigger errors | trigger lines with `2>/dev/null` / `\|\| true` and no effect check | A failed trigger still reaches a PASS/FAIL verdict |
| Missing standard prelude | first lines after the header comment differ from `mining-protocol/case-anatomy.md` §3 (no `BENCH_WORKDIR` guard, no `rebuild_worktree`) | Not the current oracle contract (exit codes, worktree path, REBUILD.sh) |
| Free-text verdict | PASS decided by `grep` for `PASS`/`ok` rather than `go test -json`, JUnit XML, Common Test `suite.log` or libtest lines for the `DDBenchOracle*` test | Code under test can print the success string |
| Network at reproduce time | downloads, hard-coded `-Dmaven.repo.local` / `GOMODCACHE` / `CARGO_HOME` | Scoring runs with `--network none` against the cache warmed at setup |

Output a pre-flight warning table before the main verification:

```
=== Pre-flight Oracle Quality Scan ===
| Case | Anti-pattern | Line | Recommendation |
|------|-------------|------|----------------|
| kafka-14334-... | Reflection field check | 65 | Replace with behavioral Mockito verify |
| nats-7718-... | FIX_COMMIT dependency | 14 | Inline test as heredoc |
```

Cases with anti-patterns may still VERIFY correctly (FAIL on buggy commit) but are **fragile oracles** — they will reject valid alternative fixes. After the main run, include a "Fragile Oracles" section in the report listing these cases and recommended remediation.

### Step 2: Run verification (sequentially to avoid resource contention)

For each case, run the following and capture output + exit code:

```bash
# Setup phase (builds online, then runs the oracle once online to warm the dependency cache;
# the warm-up must report FAIL on the buggy code, and an ERROR there fails setup)
./bench.sh setup <case-name> 2>&1
SETUP_EXIT=$?

# Reproduce phase (only if setup succeeded; offline, exactly like scoring)
if [ $SETUP_EXIT -eq 0 ]; then
    ./bench.sh reproduce <case-name> 2>&1
    REPRO_EXIT=$?     # 0 = PASS, 1 = FAIL, 2 = ERROR
fi
```

`./bench.sh list` shows which cases are already set up.

**Important resource management rules:**
- Run cases sequentially (NOT in parallel) to avoid Docker resource contention
- Set a timeout of 30 minutes for setup (builds can be slow, and setup includes one oracle run) and 5 minutes for reproduce (more for cases whose oracle loops)
- If setup fails, mark case as SETUP_FAIL and move to the next case
- Capture the last 20 lines of output for the report

### Step 3: Classify results

For each case, determine the status:

| Status | Condition |
|--------|-----------|
| VERIFIED | Setup OK + reproduce exits 1 with "FAIL:" in output, and no trigger-path errors (`command not found`, `Permission denied`, `Connection refused`) earlier in the output |
| SUSPECT | Exits 1 with "FAIL:", but trigger-path errors appear before the verdict. The FAIL may not be caused by the bug; run `/verify-oracle` |
| FIXED | Setup OK + reproduce exits 0 with "PASS:" in output (bug already fixed — wrong commit?) |
| SETUP_FAIL | Setup exited non-zero (if it failed in the warm-up because the oracle exited 2, classify as REPRO_ERROR) |
| REPRO_ERROR | Reproduce exited 2 with "ERROR:" (or without any verdict): oracle or infrastructure problem, not bug detection |
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
  SUSPECT:     N cases (FAIL, but trigger-path errors in output — run /verify-oracle)
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

- A VERIFIED result means the oracle fires correctly on the buggy commit. It does NOT confirm oracle soundness in the other direction (PASS with the fix). Use `./bench.sh validate-oracle <case> --runs 3` (and `/verify-oracle` for the semantic checks) for that.
- If many cases from the same project fail setup, the project Dockerfile likely needs updating.
- Resource contention (parallel Docker builds sharing CPU/memory) was a major friction source in past sessions — always run sequentially.
- **Fragile oracles**: A case can be VERIFIED yet still fragile. FIX_COMMIT dependencies, reflection field checks, and source-grep branching all produce oracles that reject valid alternative fixes. The pre-flight scan (Step 1.5) catches these. Remediation patterns: inline tests as heredocs (NATS pattern), use Mockito behavioral verify (Kafka pattern), ship test files as inject_test/ assets (BookKeeper pattern).
