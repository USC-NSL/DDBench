# /verify-oracle — Oracle Soundness Check

Verify that a case's reproduce script is a sound correctness oracle: FAIL on the buggy commit AND PASS after applying the fix (`cases-solution/<case>/gold.patch`). The mechanical part is `./bench.sh validate-oracle`; this skill adds the checks a script cannot do (the FAIL has the right cause, the oracle is not fix-specific).

Exit-code contract of every reproduce.sh: 0 = PASS (bug fixed), 1 = FAIL (bug present, or the worktree does not build / the code under test does not start), 2 = ERROR (oracle or infrastructure problem; inconclusive).

## Usage

```
/verify-oracle <case-name>          # verify one case
/verify-oracle <case1> <case2>      # verify multiple cases
```

## Procedure

### Step 1: Read case metadata

For each case, read `cases/<case-name>/case.yaml` and `cases-solution/<case-name>/solution.md` to extract:
- `buggy_commit` (by convention `"<fix>~1"`)
- `fix_commit` (and `fix_commit_note`, if the gold patch is a backport or there is no upstream fix commit); `solution.md`'s `- **Fix commit:**` header line names the same commit
- Build command and `docker.num_cpus`
- Whether `cases-solution/<case-name>/gold.patch` exists

If there is neither a fix commit nor a `gold.patch`, error:
```
ERROR: No fix for <case-name> (no fix_commit, no gold.patch). Cannot verify oracle in both directions.
```

### Step 2: Direction 1 — FAIL on buggy commit

```bash
./bench.sh setup <case-name>        # its warm-up already runs the oracle once online and should report FAIL
./bench.sh reset <case-name>        # pristine buggy worktree (if anything modified it)
./bench.sh reproduce <case-name>    # offline, like all scoring
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
| **Free-text verdict** | PASS decided by grepping output for `PASS`/`ok` instead of `go test -json` events, JUnit XML, Common Test `suite.log`, or libtest status lines for the exact `DDBenchOracle*` test | HIGH — code under test can print the success string |
| **Network at reproduce time** | Downloads in reproduce.sh, hard-coded `-Dmaven.repo.local`/`GOMODCACHE`/`CARGO_HOME`, a PASS path that needs dependencies the FAIL path never fetched | HIGH — scoring runs with `--network none` against the cache warmed at setup |

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
5. **Inconclusive ≠ FAIL, and code failures ≠ ERROR.** If the oracle's own machinery fails (trigger not established, harness file missing, the oracle test produced no result and no compile error explains it), the script must exit 2 with `ERROR:`. If the code under test fails to build or start, or the injected oracle test does not compile against it, that is `FAIL:`. An `ERROR` run on either side (`validate-oracle` status ERROR) means the oracle is broken.

### Step 3: Direction 2 — PASS with the gold patch

**Goal: run the oracle on the buggy commit plus the fix, exactly as scoring would run an agent's patch.**

**3a. The gold patch.** `cases-solution/<case-name>/gold.patch` is the source-only part of the fix: a unified diff relative to the repository root, without tests, docs or changelogs, that applies with `git apply` at `buggy_commit`. If it is missing, derive it from `fix_commit`. The case volume does not contain the fix: containment truncates the case repository to the buggy commit's ancestry (`git cat-file -t <fix>` fails there), so `git checkout <fix>` in the worktree can't work. Take it from the per-project **cache volume** `bug-bench-<project>-cache`, a bare full-history clone at `/cache/repo.git`:

```bash
CASE=<case-name>; PROJ=<project>; FIX=<fix_commit>; IMG=bug-bench/${PROJ}
GITC='git config --global --add safe.directory "*";'

# Make sure the fix is in the cache (bench.sh never updates it after the first clone).
docker run --rm -v bug-bench-${PROJ}-cache:/cache $IMG bash -c "$GITC
  git --git-dir=/cache/repo.git cat-file -e ${FIX}^{commit} 2>/dev/null ||
  git --git-dir=/cache/repo.git fetch -q origin '+refs/heads/*:refs/heads/*'"

# The fix's file list, then the source-only diff (drop test/doc/changelog paths).
docker run --rm --network none -v bug-bench-${PROJ}-cache:/cache:ro $IMG bash -c "$GITC
  git --git-dir=/cache/repo.git diff --stat ${FIX}~1 ${FIX}"
docker run --rm --network none -v bug-bench-${PROJ}-cache:/cache:ro $IMG bash -c "$GITC
  git --git-dir=/cache/repo.git diff ${FIX}~1 ${FIX} -- <source paths>" > cases-solution/${CASE}/gold.patch
```

Rules:
- **The patch must apply to the case's buggy commit.** `buggy_commit` must be `<fix>~1` (or `fix_commit_note` must explain the backport). A patch that does not apply makes `validate-oracle` report ERROR.
- **Submodules.** If the fix has `Subproject commit` lines, `git apply` cannot reproduce them; Direction 2 is unverified for that part. Say so.
- **Multi-commit PRs.** If the fix spans several commits, diff from the case's buggy commit to the last one, or use the PR's merge commit (`gh pr view --json mergeCommit,commits`).
- **No new third-party dependencies.** Scoring builds offline; a gold patch that needs a download cannot build.

**3b. Run both directions.**

```bash
./bench.sh validate-oracle <case-name> --runs 3 --json <scratchpad>/<case-name>.validate.json
```

It resets the worktree, runs the oracle N times on the buggy code (each run must FAIL), resets again, applies `gold.patch` with `git apply`, runs the oracle N times (each must PASS), and finally resets and rebuilds the buggy source. All runs are offline, exactly like `bench.sh reproduce`. Status and exit code:

| Status | Exit | Meaning |
|---|---|---|
| SOUND | 0 | buggy FAIL in every run and gold PASS in every run |
| UNSOUND | 1 | buggy never FAILs, or gold never PASSes |
| FLAKY | 1 | anything in between |
| ERROR | 2 | an ERROR run, a failed reset, or gold.patch does not apply |
| NO-GOLD | 3 | no gold.patch (buggy-side runs are still reported) |

The JSON (`ddbench.validate-oracle/v1`) has per-run exit codes, durations, summaries and log paths (`--log-dir`, default `.bench/logs/`). Read the gold-side logs, not only the status.

**Expected**: SOUND. To score any other candidate fix the same way: `./bench.sh eval <case-name> --patch <file.diff> --runs N --json <out.json>`.

Record:
- `fixed_exit`: per-run exit codes of the gold side
- `fixed_output`: last 10 lines of a gold-side run log
- `fixed_verdict`: PASS (correct) or FAIL (oracle unsound — false negative)

### Step 3.5: Repeatability

Use `--runs 3` at least, and more (5) for timing, metric, or race oracles. Record the per-run measured value (e.g. detection time, queue size, metric), not only the verdict. The oracle is SOUND only if every buggy run FAILs and every gold run PASSes. Any flip (FLAKY) makes it unusable (timing-sensitive): fix the oracle, then re-run. Validate at the case's `docker.num_cpus`; `BENCH_CPUS` or a smaller Docker host lowers the CPU count and bench.sh warns about it.

### Step 4: Clean up

`validate-oracle` resets the worktree and rebuilds the buggy source when it finishes. Run `./bench.sh reset <case-name>` only if something else modified the worktree.

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

Direction 2 (gold patch → expect PASS):
  Patch: cases-solution/<case-name>/gold.patch (source-only diff of <fix-commit>)
  Result: PASS (exit 0) x5/5     ← CORRECT
  Output: "PASS: Bug is fixed — process survived MONITOR inside MULTI/EXEC"

validate-oracle: SOUND (--runs 5)
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

Issue: False negative — the gold patch fails the oracle.
  This means the reproduce script flags correct behavior as buggy.
  Check: does the oracle test the right condition? Is gold.patch the complete fix?
  Does the PASS path need a dependency the warm-up never fetched (offline build)?
```

### Batch mode

When multiple cases are specified, output a summary table after individual reports:

```
| Case | Buggy → FAIL? | Gold → PASS? | Quality | Oracle |
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
- If Direction 2 fails because the patched worktree doesn't build, the issue is likely an incomplete gold.patch, a dependency the offline build cannot fetch, or the build command — not the oracle itself.
- **SOUND vs SOUND-BUT-FRAGILE**: Both pass the two-direction check, but SOUND-BUT-FRAGILE oracles use fix-specific detection (FIX_COMMIT deps, reflection field checks, source grep). They work as regression tests but will reject valid alternative fixes. For benchmark evaluation of agents, only SOUND oracles are reliable. Remediate fragile oracles before using them for agent evaluation.
