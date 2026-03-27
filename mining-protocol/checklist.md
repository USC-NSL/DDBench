# Pre-Merge Checklist

Use this checklist to validate a new case before merging it into the benchmark.

---

## File Completeness

- [ ] `cases/<case-name>/case.yaml` exists and parses correctly
- [ ] `cases/<case-name>/symptom.md` exists
- [ ] `cases/<case-name>/reproduce.md` exists
- [ ] `cases/<case-name>/verification.md` exists
- [ ] `cases/<case-name>/setup.md` exists
- [ ] `cases/<case-name>/setup.sh` exists and is executable (`chmod +x`)
- [ ] `cases/<case-name>/reproduce.sh` exists and is executable (`chmod +x`)
- [ ] `cases/<case-name>/README.md` exists
- [ ] `cases-solution/<case-name>/solution.md` exists
- [ ] `.devcontainer/<case-name>/devcontainer.json` exists
- [ ] `docker/<project>.Dockerfile` exists (or already existed for this project)

## case.yaml Correctness

- [ ] `name` matches the case directory name exactly
- [ ] `project` is lowercase and matches the Dockerfile name
- [ ] `repo` is a valid `https://` git URL ending in `.git`
- [ ] `buggy_commit` is quoted and uses the `~1` suffix
- [ ] `buggy_commit` resolves to a valid commit (`git rev-parse <commit>`)
- [ ] `submodules` is `true` or `false` (not quoted)
- [ ] `build.command` builds the project from a clean worktree
- [ ] `build.binary` points to the correct output path (relative to worktree root)
- [ ] `docker.caps` is a YAML inline list (use `[]` if empty)
- [ ] `docker.min_cpus` is set (default: 1)

## Script Correctness

### setup.sh
- [ ] Docker preamble is present and identical to the standard template
- [ ] Host fallback installs dependencies via `apt-get`
- [ ] Host fallback clones with correct flags (`--recurse-submodules` if needed)
- [ ] Host fallback checks out `buggy_commit` (not fix commit)
- [ ] Script is idempotent (re-running skips completed steps)
- [ ] Build produces the binary at the path declared in case.yaml

### reproduce.sh
- [ ] Docker preamble is present and identical to the standard template
- [ ] Checks for binary existence and errors clearly if missing
- [ ] Cleans up from previous runs before starting
- [ ] Defines `cleanup` function with `trap cleanup EXIT`
- [ ] Final output is exactly `PASS: Bug is fixed — <description>` or `FAIL: Bug is present — <description>`
- [ ] Exits with code 0 (PASS) or 1 (FAIL)
- [ ] Uses unique port number (convention: `1<issue#>`)
- [ ] Handles `REBUILD.sh` if present (`[ -f "$WORK_DIR/REBUILD.sh" ] && bash "$WORK_DIR/REBUILD.sh"`)

## Documentation Quality

### symptom.md
- [ ] Describes observable behavior only (no root cause hints)
- [ ] Includes specific error signals (SIGABRT, "DATA RACE", etc.)
- [ ] Would not help an agent locate the buggy code directly

### reproduce.md
- [ ] Steps are numbered and complete
- [ ] Commands include all flags and ports
- [ ] "Expected result (bug present)" section is present

### verification.md
- [ ] Contains executable bash snippet
- [ ] PASS/FAIL criteria are clearly stated
- [ ] References specific signals or exit codes

### README.md
- [ ] Metadata table is complete (Project, Issue, Language, Category)
- [ ] Quick Start section includes `./setup.sh` and `./reproduce.sh`
- [ ] Links to all 4 documentation files

### solution.md
- [ ] Links to fix PR and commit
- [ ] Root cause is explained at code level
- [ ] Fix description explains what changed
- [ ] "How to apply" section has correct checkout + build commands

## Docker Validation

- [ ] `./bench.sh setup <case-name>` completes successfully
- [ ] `./bench.sh reproduce <case-name>` outputs `FAIL: ...` (bug present on buggy commit)
- [ ] `./bench.sh shell <case-name>` starts an interactive shell
- [ ] Inside shell: applying the fix + rebuilding + re-running reproduce gives `PASS`
- [ ] `./bench.sh clean <case-name>` followed by `setup` + `reproduce` still works (clean slate)
- [ ] Second `setup` run is fast (idempotent — skips clone and build)

## Selection Criteria Compliance

### Dual-reasoning requirement
- [ ] The bug cannot be diagnosed by code reading alone (requires runtime observation to understand the trigger)
- [ ] The bug cannot be diagnosed by runtime evidence alone (requires code analysis to identify the root cause)
- [ ] The symptom.md describes the runtime/cluster context without pointing to the code

### Fix locus
- [ ] `solution.md` names the component and lists the changed files
- [ ] The fix is localized (clear component, preferably 1-3 files)

### Oracle soundness
- [ ] `reproduce.sh` produces FAIL on the buggy commit (confirmed)
- [ ] `reproduce.sh` produces PASS after applying the fix commit (confirmed)
- [ ] No false positives (buggy code cannot accidentally pass)
- [ ] No false negatives (fixed code does not spuriously fail)

### Diagnosis chain
- [ ] `solution.md` includes a diagnosis chain documenting the reasoning from symptom to root cause
- [ ] The chain references both runtime evidence and code-level reasoning

## No Answer Leakage

- [ ] `symptom.md` does not mention function names, variable names, or code paths from the fix
- [ ] `reproduce.md` does not reference the fix PR or commit
- [ ] `verification.md` does not hint at the root cause
- [ ] `setup.sh` and `reproduce.sh` do not contain comments revealing the fix
- [ ] `solution.md` is in `cases-solution/`, NOT in `cases/`
- [ ] The GitHub issue text does not trivially reveal the fix (if it does, the case is excluded — see selection criteria)

## Index and Metadata

- [ ] Row added to `index.md` with correct rank, project, URL, description, and folder name
- [ ] If new project: `CLAUDE.md` "Covered projects" table updated
- [ ] Total case count in `index.md` header updated
