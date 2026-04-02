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
- **Fragile oracles**: A case can be VERIFIED yet still fragile. FIX_COMMIT dependencies, reflection field checks, and source-grep branching all produce oracles that reject valid alternative fixes. The pre-flight scan (Step 1.5) catches these. Remediation patterns: inline tests as heredocs (NATS pattern), use Mockito behavioral verify (Kafka pattern), ship test files as inject_test/ assets (BookKeeper pattern).
