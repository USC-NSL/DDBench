# Pre-Merge Checklist

Use this checklist to validate a new case before merging it into the benchmark.

---

## File Completeness

- [ ] `cases/<case-name>/case.yaml` exists and parses (`./bench.sh info <case-name>` prints its settings)
- [ ] `cases/<case-name>/reproduce.sh` exists and is executable (`chmod +x`)
- [ ] `cases/<case-name>/symptom.md` exists
- [ ] `cases/<case-name>/README.md` exists
- [ ] `cases/<case-name>/reproduce.md` exists
- [ ] Oracle harness files the oracle reads (`inject_test.go`, `inject_test/`, ...) are in the case directory
- [ ] No per-case setup script or setup document (`case.yaml` + `./bench.sh setup` replace them), and no stray template files (`solution.md`, `devcontainer.json`, other reproduce variants) in `cases/<case-name>/`
- [ ] `cases-solution/<case-name>/solution.md` exists
- [ ] `cases-solution/<case-name>/gold.patch` exists
- [ ] `.devcontainer/<case-name>/devcontainer.json` exists (placeholders and `CASE_UID` substituted)
- [ ] `docker/<project>.Dockerfile` exists (or already existed for this project)
- [ ] Optional `cases/<case-name>/context/` follows the rules in "No Answer Leakage" below

## case.yaml Correctness

- [ ] `name` matches the case directory name exactly
- [ ] `project` is lowercase and matches the Dockerfile name
- [ ] `repo` is a valid `https://` git URL ending in `.git`
- [ ] `buggy_commit` is quoted and resolves in the full clone (convention: `"<fix-sha>~1"`)
- [ ] `fix_commit` is the quoted 40-char upstream fix SHA, or `null` / a backport with `fix_commit_note` explaining
- [ ] `resolve_time` has `date`, `source` (`confirmed_fix_commit_date` or `issue_close_date`) and `reference`
- [ ] `submodules` is `true` or `false` (not quoted)
- [ ] `build.command` builds the project from a clean worktree, and offline once the dependency cache is warm
- [ ] `build.binary` points to the correct output path (relative to worktree root), or `""`
- [ ] `docker.caps` is a YAML inline list (use `[]` if empty)
- [ ] `docker.num_cpus` is set to what the build and oracle need
- [ ] `docker.seccomp_unconfined` only if required; `docker.offline: false` only as a justified last resort
- [ ] Exactly 2-space indentation, inline lists, no trailing comments after nested values

## reproduce.sh Correctness

- [ ] Header comment ends with the exit-code summary, followed by the standard prelude, verbatim (see case-anatomy.md §3)
- [ ] Registers `cleanup` with `trap cleanup EXIT`, then calls `rebuild_worktree` before running anything else
- [ ] Exit contract: `pass` (0) only when the bug is fixed; `fail` (1) when the bug is present or the code under test does not build, start, or reach the baseline state; `error` (2) only for failures of the oracle's own machinery
- [ ] Output ends with exactly one `PASS: ...`, `FAIL: ...` or `ERROR: ...` line
- [ ] Injected oracle tests are written fresh each run under `DDBenchOracle*` names (`zz_ddbench_oracle_*` files) and removed, with their build outputs and reports, in an `EXIT` trap
- [ ] Verdict comes from structured output for the exact oracle test (`go test -json`, JUnit XML, Common Test `suite.log`, libtest status lines) or from process state / protocol replies, never from free text
- [ ] Scratch files in `$RUN_DIR`; nothing written into the worktree outside injected files that the trap removes
- [ ] Harness files read from `$CASE_DIR`
- [ ] Downloads nothing at reproduce time; no hard-coded cache paths (`-Dmaven.repo.local`, `GOMODCACHE`, `CARGO_HOME`, ...)
- [ ] `cleanup` + `trap cleanup EXIT` defined BEFORE starting processes; kills leftovers from previous runs
- [ ] Server readiness uses active polling with bounded client calls, not blind `sleep`
- [ ] Uses unique port numbers (convention: `1<issue#>`)
- [ ] No `set -e`, no `sudo`
- [ ] `bash -n cases/<case-name>/reproduce.sh` passes

## Documentation Quality

### symptom.md
- [ ] Describes observable behavior only (no root cause hints)
- [ ] Includes specific error signals (SIGABRT, "DATA RACE", etc.)
- [ ] Describes the runtime/cluster context that triggers the bug
- [ ] Would not help an agent locate the buggy code directly
- [ ] Does not mention `context/` or link the upstream issue/PR
- [ ] Cross-referenced against `solution.md` — none of the following appear:
  - [ ] Function, method, or variable names from the fix diff
  - [ ] Struct field names or internal constants from the buggy code path
  - [ ] File paths pointing to the fix location
  - [ ] Fix strategy descriptions ("make X idempotent", "add synchronization")
  - [ ] Error messages only visible in source code (not user-facing output)
  - [ ] PR numbers or commit hashes of the fix

### reproduce.md
- [ ] Steps are numbered, complete, and run inside `./bench.sh shell <case-name>`
- [ ] Commands include all flags and ports
- [ ] "Expected result (bug present)" section is present
- [ ] "Oracle verdict" section states briefly what FAIL, PASS and ERROR mean for this oracle (matching `reproduce.sh`), with specific signals or exit codes where they apply

### README.md
- [ ] Metadata table is complete (Project, Issue, Language, Category)
- [ ] Quick Start uses `./bench.sh setup` / `reproduce` / `shell`
- [ ] Links to symptom.md, reproduce.md and reproduce.sh

### solution.md and gold.patch
- [ ] solution.md starts with `# Solution: <Project> #<issue>` and the `- **Issue:**`, `- **Fix commit:**`, `- **Gold patch:**` header lines
- [ ] Root cause is explained at code level
- [ ] Fix description explains what changed
- [ ] gold.patch is a source-only unified diff relative to the repository root (no tests, docs, changelogs) that applies with `git apply` at `buggy_commit`
- [ ] gold.patch adds no third-party dependencies (scoring builds offline)

## Docker Validation

- [ ] `./bench.sh setup <case-name>` completes; the warm-up reports FAIL on the buggy code
- [ ] `./bench.sh reproduce <case-name>` exits 1 with `FAIL: ...` (bug present on the buggy commit)
- [ ] `reproduce` output shows no trigger-path errors (`command not found`, `Permission denied`, …) before the verdict
- [ ] `./bench.sh validate-oracle <case-name>` reports `SOUND` (`--runs 3` or more for timing- or race-based oracles); keep the `--json` result
- [ ] `./bench.sh shell <case-name>` starts, and `bash /bench/reproduce.sh` gives the same verdict inside it
- [ ] `./bench.sh clean <case-name>` followed by `setup` + `reproduce` still works (clean slate)
- [ ] Second `setup` run is fast (repository exists, cache already warm)

## Selection Criteria Compliance

### Dual-reasoning requirement
- [ ] The bug cannot be diagnosed by code reading alone (requires runtime observation to understand the trigger)
- [ ] The bug cannot be diagnosed by runtime evidence alone (requires code analysis to identify the root cause)
- [ ] The symptom.md describes the runtime/cluster context without pointing to the code

### Fix locus
- [ ] `solution.md` names the component and lists the changed files
- [ ] The fix is localized (clear component, preferably 1-3 files)

### Oracle soundness
- [ ] Buggy worktree FAILs and gold.patch PASSes in every run (`validate-oracle` SOUND)
- [ ] The FAIL condition measures the behavior the fix diff changes
- [ ] Metric/threshold oracles: a negative control (bug trigger removed) does not FAIL, with a clear margin
- [ ] Trigger is confirmed in-script; inconclusive runs exit 2 with `ERROR:`
- [ ] No fix-only config/APIs, generous detection windows (alternative fixes pass)
- [ ] No false positives (buggy code cannot accidentally pass)
- [ ] No false negatives (fixed code does not spuriously fail)

### Diagnosis chain
- [ ] `solution.md` includes a diagnosis chain documenting the reasoning from symptom to root cause
- [ ] The chain references both runtime evidence and code-level reasoning

## No Answer Leakage

- [ ] `symptom.md` does not mention function names, variable names, or code paths from the fix
- [ ] `README.md` and `reproduce.md` do not reference the fix PR or commit or hint at the root cause
- [ ] `reproduce.sh` comments and printed messages do not reveal the fix or root-cause mechanism (defense in depth; agents never see `/bench`)
- [ ] `context/` is observational only (see authoring-guide.md "Authoring context/"): debug context a developer could gather at the buggy commit before knowing the fix; no diagnosis, root cause or fix direction; no links to the upstream issue, PR or fix; no `reproduce.sh` output, PASS/FAIL verdicts, injected oracle tests, or oracle thresholds, windows, or trigger parameters. `/sanitize <case-name>` passes.
- [ ] `solution.md` and `gold.patch` are in `cases-solution/`, NOT in `cases/`
- [ ] The GitHub issue text does not trivially reveal the fix (if it does, the case is excluded — see selection criteria)

## Index and Metadata

- [ ] Row added to `index.md` with correct rank, project, URL, description, and folder name
- [ ] If new project: "Covered projects" tables (`CLAUDE.md`, repository `README.md`) updated
- [ ] Total case counts updated wherever they are stated
- [ ] `validate-oracle` result recorded with the release results (`docs/oracle-validation.md`, `registry/oracle_validation.json`)
