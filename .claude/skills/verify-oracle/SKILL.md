# /verify-oracle — Oracle Soundness Check

Verify that a case's reproduce script is a sound correctness oracle: FAIL on the buggy commit AND PASS after applying the fix.

## Usage

```
/verify-oracle <case-name>          # verify one case
/verify-oracle <case1> <case2>      # verify multiple cases
```

## Procedure

### Step 1: Read case metadata

For each case, read `cases/<case-name>/case.yaml` and `cases-solution/<case-name>/solution.md` to extract:
- `buggy_commit` (the `~1` value from case.yaml)
- Fix commit hash (from solution.md → "Commit" field)
- Build command (from case.yaml)

If `solution.md` does not exist or doesn't contain a fix commit, error:
```
ERROR: No fix commit found for <case-name>. Cannot verify oracle in both directions.
```

### Step 2: Direction 1 — FAIL on buggy commit

```bash
# Ensure we're on the buggy commit (bench.sh setup does this)
./bench.sh setup <case-name>
./bench.sh reproduce <case-name>
```

**Expected**: exit code 1 with "FAIL:" in output.

Record:
- `buggy_exit`: exit code
- `buggy_output`: last 10 lines of output
- `buggy_verdict`: FAIL (correct) or PASS (oracle unsound — false positive)

### Step 3: Direction 2 — PASS on fix commit

This requires applying the fix inside the container and rebuilding:

```bash
./bench.sh shell <case-name> --cmd "
  cd /workspace/worktrees/<case-name> &&
  git checkout <fix-commit> &&
  <rebuild-command> &&
  bash /bench/reproduce.sh
"
```

If the case uses submodules, also run `git submodule update --init --recursive` after checkout.

**Expected**: exit code 0 with "PASS:" in output.

Record:
- `fixed_exit`: exit code
- `fixed_output`: last 10 lines of output
- `fixed_verdict`: PASS (correct) or FAIL (oracle unsound — false negative)

### Step 4: Reset to buggy commit

After verification, reset the worktree back to the buggy commit so the case is ready for future use:

```bash
./bench.sh reset <case-name>
```

### Step 5: Report

```
=== Oracle Soundness Report: <case-name> ===

Direction 1 (buggy commit → expect FAIL):
  Commit: <buggy-commit>
  Result: FAIL (exit 1)          ← CORRECT
  Output: "FAIL: Bug is present — process crashed (exit code 134, SIGABRT=134)"

Direction 2 (fix commit → expect PASS):
  Commit: <fix-commit>
  Result: PASS (exit 0)          ← CORRECT
  Output: "PASS: Bug is fixed — process survived MONITOR inside MULTI/EXEC"

Oracle verdict: SOUND
```

If either direction fails:

```
Oracle verdict: UNSOUND

Issue: False positive — buggy code passes the oracle.
  This means the reproduce script does not reliably trigger the bug.
  Check: timing sensitivity, iteration count, race window.

  — OR —

Issue: False negative — fixed code fails the oracle.
  This means the reproduce script flags correct behavior as buggy.
  Check: does the oracle test the right condition? Is the fix commit correct?
```

### Batch mode

When multiple cases are specified, output a summary table after individual reports:

```
| Case | Buggy → FAIL? | Fixed → PASS? | Oracle |
|------|---------------|---------------|--------|
| dragonfly-6614-monitor-multiexec | FAIL (correct) | PASS (correct) | SOUND |
| etcd-19172-embed-data-race | FAIL (correct) | FAIL (wrong!) | UNSOUND |
```

### Notes

- This is the strongest validation you can run. It confirms the oracle is not accidentally correct in one direction only.
- Oracle soundness is a mandatory selection criterion (see mining-protocol/selection-criteria.md #4).
- For race/flaky cases, Direction 2 may require multiple runs to confirm PASS is reliable. Run at least 3 times.
- If Direction 2 fails because the fix commit doesn't build, the issue is likely the build command or missing submodule updates — not the oracle itself.
