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

### Step 2.5: Oracle quality scan

Before running Direction 2, scan `reproduce.sh` for anti-patterns that make the oracle **fix-specific** (it will FAIL on buggy and PASS on the upstream fix, but FAIL on valid alternative fixes). These are fragile oracles that pass the soundness check but reject correct work from agents/humans.

Check for these anti-patterns:

| Anti-pattern | Detection | Severity |
|---|---|---|
| **FIX_COMMIT dependency** | `grep 'FIX_COMMIT='` | HIGH — test code pulled from specific commit |
| **`git show` from fix** | `grep 'git show.*FIX_COMMIT'` | HIGH — test extracted at runtime from fix |
| **`git checkout` from fix** | `grep 'git checkout.*FIX_COMMIT'` | HIGH — files pulled from fix commit tree |
| **Reflection as oracle** | `getDeclaredField`/`getDeclaredMethod` used in PASS/FAIL assertion (not test setup) | HIGH — checks code structure, not behavior |
| **Source grep branching** | `grep -q` on production source to branch test logic | MEDIUM — detects fix text, not fix effect |
| **`sed -i` on production** | `sed -i` targeting `src/main` paths | MEDIUM — injects accessors to read internal state |

If any HIGH-severity anti-pattern is found, emit a warning:

```
WARNING: Oracle is fix-specific (fragile)
  Anti-pattern: FIX_COMMIT dependency (line 14)
  Risk: Oracle will reject valid alternative fixes
  Remediation: Inline test as heredoc or ship as inject_test/ files
```

The oracle can still be SOUND (passes both directions with the upstream fix) but should be flagged as **SOUND-BUT-FRAGILE** in the report. This means it works as a regression test for the specific upstream fix but NOT as a general correctness oracle for evaluating agent-generated patches.

**Remediation patterns (proven):**
- **NATS cases**: Replace `git show FIX_COMMIT` with inline heredoc test function (`cat >> "$TEST_FILE" << 'TESTEOF'`)
- **Kafka cases**: Replace reflection field checks with behavioral Mockito `verify()` or `mockingDetails`; use cross-version `Answer` mocks for API compatibility; use reflection only for method invocation (API compat), not detection
- **BookKeeper cases**: Ship test infrastructure as static `inject_test/` files in the case directory instead of `git checkout FIX_COMMIT`
- **General**: Tests should verify *observable behavior* (method calls, return values, exception presence/absence, state after operations) not *code structure* (field existence, method override presence, source text patterns)

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

If the oracle passes both directions but has quality anti-patterns (Step 2.5):

```
Oracle verdict: SOUND-BUT-FRAGILE

Quality issues found:
  - FIX_COMMIT dependency (line 14): test extracted from fix commit
  Recommendation: Inline test as heredoc or ship as inject_test/ files
  Impact: Oracle will reject valid alternative fixes from agents/humans
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
| Case | Buggy → FAIL? | Fixed → PASS? | Quality | Oracle |
|------|---------------|---------------|---------|--------|
| dragonfly-6614-monitor-multiexec | FAIL (correct) | PASS (correct) | clean | SOUND |
| nats-7718-subscription-leak | FAIL (correct) | PASS (correct) | clean | SOUND |
| kafka-14334-delayed-fetch-purgatory | FAIL (correct) | PASS (correct) | FIX_COMMIT dep | SOUND-BUT-FRAGILE |
| etcd-19172-embed-data-race | FAIL (correct) | FAIL (wrong!) | clean | UNSOUND |
```

### Notes

- This is the strongest validation you can run. It confirms the oracle is not accidentally correct in one direction only.
- Oracle soundness is a mandatory selection criterion (see mining-protocol/selection-criteria.md #4).
- For race/flaky cases, Direction 2 may require multiple runs to confirm PASS is reliable. Run at least 3 times.
- If Direction 2 fails because the fix commit doesn't build, the issue is likely the build command or missing submodule updates — not the oracle itself.
- **SOUND vs SOUND-BUT-FRAGILE**: Both pass the two-direction check, but SOUND-BUT-FRAGILE oracles use fix-specific detection (FIX_COMMIT deps, reflection field checks, source grep). They work as regression tests but will reject valid alternative fixes. For benchmark evaluation of agents, only SOUND oracles are reliable. Remediate fragile oracles before using them for agent evaluation.
