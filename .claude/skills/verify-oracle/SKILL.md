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
| **`sudo` in reproduce.sh** | `grep -n 'sudo '` | HIGH — the images ship no `sudo` (and `bench.sh reproduce` already runs as root); the step silently fails (`sudo: command not found`) and the trigger never happens |
| **Trigger errors swallowed** | Fault-injection/trigger lines ending in `2>/dev/null`, `\|\| true`, or with no exit-status check | HIGH — a failed trigger falls through to the verdict, so FAIL/PASS no longer reflects the bug |
| **Fix-only config / API** | Oracle sets or reads config options, commands, or log strings that only exist in the fix diff | HIGH — buggy build rejects them (false FAIL) and alternative fixes never produce them |
| **Bare metric threshold** | PASS/FAIL decided by `du`, memory, latency, or counter vs. a constant | MEDIUM — must be backed by the negative control in Step 2.6 |

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

### Step 2.6: Oracle validity checks (Direction 1 alone proves nothing)

A FAIL on the buggy commit is necessary but **not sufficient**. An oracle can FAIL on buggy code for reasons unrelated to the bug, and then it FAILs on the fix too. (Real example: kvrocks-3356 measured data-dir growth after a 1M-SET benchmark. That size is ~550MB with or without the bug, and it even FAILed with no replica attached.) Before Direction 2, check:

1. **Read the Direction 1 output, not just the verdict.** Look for `command not found`, `Permission denied`, `No such file`, `Connection refused`, and similar errors before the verdict line. Any error in the trigger path means the FAIL is meaningless. Reclassify it as REPRO_ERROR and fix the script.
2. **Semantic check against the fix diff.** Read the fix commit message and diff, and name the observable behavior the fix changes. Does the oracle's FAIL condition measure *that* behavior? If the fix doesn't touch the quantity the oracle measures (e.g. the fix adds a send timeout and the oracle measures disk usage), the oracle is UNSOUND, whatever Direction 1 says.
3. **Negative control** (mandatory for METRIC/threshold oracles, recommended for all). Run the oracle's scenario on the buggy build with the bug trigger removed or neutralized, e.g. no fault injected or the bug-relevant component absent. The control must not FAIL. Also record the measured value against the threshold: if buggy-build values sit within ~2× of the threshold, the margin is too thin.
4. **Trigger took effect.** The script must check that the fault actually happened (e.g. send queue non-empty, process actually stopped, partition actually dropping packets), not just that the command ran. Fault injection must hit the real traffic path. Example: replication connections are opened *by the replica to the master*, so an iptables rule on the replica's listening port never matches replication traffic.
5. **Inconclusive ≠ FAIL, and code failures ≠ ERROR.** If the oracle's own machinery fails (trigger not established, injected test doesn't compile), the script must exit 2 with `ERROR:`. If the code under test fails to build or start, that is `FAIL:`. An `ERROR` on either the buggy or the fixed commit during validation means the oracle is broken.

### Step 3: Direction 2 — PASS on fix commit

**Goal: run the oracle on exactly the fix commit's code, and prove it.**

**Where the fix comes from.** The fix commit hash is in `solution.md` (Step 1). The case volume doesn't contain it: containment cuts the case repo off at the buggy commit (`git cat-file -t <fix>` fails there), so `git checkout <fix>` in the case workspace can't work. The code comes from the per-project **cache volume** `bug-bench-<project>-cache`, a full-history clone of upstream at `/cache/repo.git`. If the cache predates the fix, fetch it from upstream into the cache. Apply the fix to a **scratch copy** of the case volume; never modify the case volume itself.

**Why this is the real fix commit.** The case's buggy commit is `<fix>~1`. Applying the *full* `git diff <fix>~1 <fix>` to a clean checkout of `<fix>~1` reproduces `<fix>`'s tree exactly. Step 3c proves it: the scratch tree's `git write-tree` hash must equal `git rev-parse <fix>^{tree}`. Equal hashes mean byte-identical source for every tracked file.

```bash
CASE=<case-name>; PROJ=<project>; FIX=<fix-commit from solution.md>; SCR=<scratchpad-dir>
IMG=bug-bench/${PROJ}; GITC='git config --global safe.directory "*";'

# 3a. From the cache: make sure the fix exists (fetch from upstream if not), then export the
#     expected start point, the expected tree hash, and the FULL diff (no path exclusions).
docker run --rm -v bug-bench-${PROJ}-cache:/c -v $SCR:/out $IMG bash -c "$GITC cd /c/repo.git;
  git cat-file -e ${FIX}^{commit} 2>/dev/null || git fetch -q origin ${FIX} || exit 1;
  git rev-parse ${FIX}~1 > /out/parent; git rev-parse ${FIX}^{tree} > /out/tree;
  git diff --binary ${FIX}~1 ${FIX} > /out/fix.patch"

# 3b. Scratch copy of the case volume
docker volume create ${CASE}-fixed-scratch
docker run --rm -v bug-bench-case-${CASE}-src:/from:ro -v ${CASE}-fixed-scratch:/to alpine cp -a /from/. /to/

# 3c. Check the start point, apply, and PROVE the tree equals the fix commit's tree
docker run --rm -v ${CASE}-fixed-scratch:/workspace -v $SCR:/in:ro $IMG bash -c "$GITC cd /workspace/worktrees/${CASE};
  [ \"\$(git rev-parse HEAD)\" = \"\$(cat /in/parent)\" ] || { echo 'START != <fix>~1'; exit 1; };
  [ -z \"\$(git status --porcelain --untracked-files=no)\" ] || { echo 'DIRTY WORKTREE'; exit 1; };
  git apply --index /in/fix.patch || exit 1;
  [ \"\$(git write-tree)\" = \"\$(cat /in/tree)\" ] && echo TREE-IDENTICAL || { echo TREE-MISMATCH; exit 1; }"

# 3d. Clean build with case.yaml's build command (fresh build dir, same as setup does)
docker run --rm --cpus=<num_cpus> -v ${CASE}-fixed-scratch:/workspace $IMG bash -c "$GITC
  cd /workspace/worktrees/${CASE} && rm -rf <build-dir> && <case.yaml build.command>"

# 3e. Run the oracle against the scratch volume, mounted the way bench.sh does it, plus case.yaml caps
docker run --rm <caps> -v ${CASE}-fixed-scratch:/workspace -v $PWD/cases/${CASE}:/bench:ro \
  -w /workspace/worktrees/${CASE} -e BENCH_WORKSPACE=/workspace/worktrees $IMG bash /bench/reproduce.sh
```

Rules:
- **TREE-MISMATCH, START mismatch, or a dirty worktree → stop.** Don't run the oracle on a hybrid tree. Run `./bench.sh reset <case>`, or fix `buggy_commit` in case.yaml (it must be `<fix>~1`).
- **Submodules.** If the diff has `Subproject commit` lines, run `git submodule update --init --recursive` in the scratch copy after 3c. Then check each submodule's HEAD against `git ls-tree <fix> <path>` from the cache. If the new submodule commits can't be fetched, Direction 2 is unverified; say so.
- **Multi-commit PRs.** If the fix spans several commits, set `FIX` to the last one. Its first parent must still be the case's buggy commit; otherwise use the PR's merge commit (`gh pr view --json mergeCommit,commits`).
- **Incremental builds are fine while iterating** on the oracle. The verdict you record must come from 3d's clean build.

**Expected**: exit code 0 with "PASS:" in output.

Record:
- `fixed_exit`: exit code
- `fixed_output`: last 10 lines of output
- `fixed_verdict`: PASS (correct) or FAIL (oracle unsound — false negative)

### Step 3.5: Repeatability

Run each direction **at least 3 times** (≥5 for timing, metric, or race oracles). Independent containers can run in parallel, since each has its own network namespace. Record the per-run measured value (e.g. detection time, queue size, metric), not only the verdict. The oracle is SOUND only if every buggy run FAILs and every fixed run PASSes. Any flip makes it UNSOUND (timing-sensitive): fix the oracle, then re-run.

### Step 4: Clean up

The case volume was never modified, so no reset is needed. Delete the scratch volume (`docker volume rm ${CASE}-fixed-scratch`). Run `./bench.sh reset <case-name>` only if something did modify the case workspace.

### Step 5: Report

```
=== Oracle Soundness Report: <case-name> ===

Direction 1 (buggy commit → expect FAIL):
  Commit: <buggy-commit>
  Result: FAIL (exit 1) x5/5     ← CORRECT
  Output: "FAIL: Bug is present — process crashed (exit code 134, SIGABRT=134)"

Validity (Step 2.6):
  Trigger errors in output: none
  Fix changes measured behavior: yes — <one line>
  Negative control: PASS (<measured value> vs threshold <T>)  | n/a (non-metric)
  Trigger confirmed in-script: yes — <how>

Direction 2 (fix commit → expect PASS):
  Commit: <fix-commit> (scratch volume; tree hash verified = <fix>^{tree}; clean build)
  Result: PASS (exit 0) x5/5     ← CORRECT
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

Issue: FAIL for the wrong reason — buggy code FAILs, but the negative control
  also FAILs, the trigger errored, or the fix doesn't change what is measured.
  The oracle measures the workload/environment, not the bug. Redesign it to
  observe the behavior the fix changes.

  — OR —

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
- Run both directions repeatedly (Step 3.5). A single run in each direction isn't a soundness result.
- A case that has only ever been checked in Direction 1 is **unverified**, not SOUND. kvrocks-3356 was recorded as "bug confirmed" in tier-1 replay validation while its oracle could not tell buggy code from fixed code.
- If Direction 2 fails because the fix commit doesn't build, the issue is likely the build command or missing submodule updates — not the oracle itself.
- **SOUND vs SOUND-BUT-FRAGILE**: Both pass the two-direction check, but SOUND-BUT-FRAGILE oracles use fix-specific detection (FIX_COMMIT deps, reflection field checks, source grep). They work as regression tests but will reject valid alternative fixes. For benchmark evaluation of agents, only SOUND oracles are reliable. Remediate fragile oracles before using them for agent evaluation.
