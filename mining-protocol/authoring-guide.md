# Authoring Guide

Step-by-step walkthrough for adding a new case to the benchmark. Everything runs in Docker
through `bench.sh`; there is no host workflow.

---

## Phase 1: Bug Selection and Validation

### 1.1 Identify a candidate bug

Find a GitHub issue in a distributed system project that:
- Has a merged fix (closed issue with linked PR)
- Describes a concrete, reproducible failure
- Falls within the [selection criteria](selection-criteria.md)

### 1.2 Locate the fix commit

```bash
gh pr view <PR-URL> --json mergeCommit,commits
# Or check the PR's "Commits" tab on GitHub
```

Record the fix commit hash (`fix_commit` in case.yaml). The buggy commit is `<fix-commit>~1`.

Then write down, from the issue, the fix commit message, and the diff: the **defect**, its **observable effect**, and **what the fix changes observably**. If the PR adds a test, read its assertions. Check that the issue's terms match the diff (kvrocks-3356's "WAL exhaustion" meant WAL pruned under a blocked replica, not disk full). The oracle in 2.6 must observe what the fix changes.

### 1.3 Verify reproduction in the container

Before writing the rest of the case, reproduce the bug by hand in the project's container.
Write `case.yaml` first (2.2), then:

```bash
./bench.sh setup <case-name> --no-warm   # no oracle yet, so skip the warm-up
./bench.sh shell <case-name>             # worktree at /workspace/src, at the buggy commit
# Build and trigger the bug following the issue description
```

The case repository contains only the buggy commit's ancestry; the fix is not in it. If you
cannot reproduce reliably, the bug is not suitable. If `docker/<project>.Dockerfile` does not
exist yet, do Phase 3 first.

### 1.4 Evaluate diagnostic depth

Before investing in case files, apply the three gatekeeping tests:

**Dual-reasoning test**: Would a debugger need to combine code reading with runtime observation to reach the root cause?
- Ask: "Could I diagnose this from a stack trace / error log alone?" If yes → too shallow.
- Ask: "Could I diagnose this from reading the code without ever running the system?" If yes → purely static bug, not suitable.
- The sweet spot: runtime evidence (crash signal, cluster behavior, replication failure) points toward a subsystem, but code reasoning is needed to understand *why* that subsystem fails under those conditions.

**Fix locus test**: Can you name the component and the 1-3 files where the fix lives? If the fix is scattered across many unrelated modules with no clear center, the case is hard to evaluate.

**Issue text test**: Read the GitHub issue. Does it describe the root cause and fix location explicitly? If an agent could derive the patch just by reading the issue, the case bypasses diagnosis entirely.

---

## Phase 2: Create Case Files

### 2.1 Scaffold the files

Run the commands in [templates/README.md](templates/README.md#how-to-use) (or `/newcase`).
They copy each template to its own destination: the case files and one reproduce variant
into `cases/<case>/`, `solution.md` into `cases-solution/<case>/`, and the devcontainer
template into `.devcontainer/<case>/devcontainer.json`, then fill in the case name, project
and `CASE_UID`. Never copy the templates directory wholesale.

### 2.2 Fill in case.yaml

Start here — this drives all automation. See [case-anatomy.md](case-anatomy.md#1-caseyaml) for the schema.

Key decisions:
- **build.command**: Test it inside the container (`./bench.sh shell`). Multi-step builds may use a YAML block scalar (`|`). It runs online at setup and offline before every oracle run, so it must not need the network once the dependency cache is warm.
- **build.binary**: Path relative to the worktree root. Use `""` for test-only cases (Go libraries)
- **fix_commit** / **resolve_time**: from 1.2 and the issue (see case-anatomy.md)
- **docker.num_cpus**: what the build and the oracle need; timing-sensitive oracles are validated at this CPU count
- **docker.caps**: Only add capabilities that are actually required. Test without them first
- **docker.offline**: leave unset. `false` only as a last resort (see [docker-containment.md](docker-containment.md#offline-scoring-and-the-dependency-cache))

### 2.3 Write symptom.md

Describe the bug as someone encountering it for the first time would. Do NOT reveal the root cause. This file is copied into the worktree as `SYMPTOM.md` and is the agent's starting point in both evaluation conditions.

Good: "The server crashes with SIGABRT when MONITOR is called twice inside MULTI/EXEC."
Bad: "The ChangeMonitor function is not idempotent." (this reveals the fix)

### 2.4 Write reproduce.md

Document the manual reproduction steps you validated in Phase 1, as commands run inside `./bench.sh shell <case>`. Include exact commands, ports, and expected output. End with the "Oracle verdict" section: one or two sentences each on what FAIL, PASS and ERROR mean for this oracle, matching what `reproduce.sh` checks (template: `templates/reproduce.md`). Fill it in once the oracle is final.

### 2.5 Write reproduce.sh

Start from the template that fits (see [templates/README.md](templates/README.md#reproduce-templates)); keep its header comment and prelude. The full contract is in [case-anatomy.md](case-anatomy.md#3-reproducesh). Then:
1. Register `cleanup` with `trap cleanup EXIT`, then call `rebuild_worktree` before running anything else (a failed `REBUILD.sh` is FAIL)
2. Clean up leftovers from previous runs (processes, ports)
3. Start the service (if server-based); if the code under test does not start, `fail`
4. Inject the oracle test fresh under a `DDBenchOracle*` name (if test-based), reading harness files from `$CASE_DIR`
5. Trigger the bug, then **confirm the trigger took effect** (otherwise `error`, exit 2)
6. Check the outcome: observe the behavior the fix changes (1.2), using bounded client calls (`timeout 5 ...`), and decide from structured output (test reports, process state, protocol replies)
7. End with `pass "..."`, `fail "..."` or, only when the oracle's own machinery failed, `error "..."`

Agents never see `/bench`, but as defense in depth, reproduce.sh comments and messages describe what is observed, not the root-cause mechanism. Don't use options, commands, or log strings that exist only in the fix, and make detection windows generous so alternative fixes pass. Scratch files go in `$RUN_DIR`, and nothing may be downloaded at reproduce time.

Choose the right reproduction strategy for the bug type:

| Bug Type | Template |
|----------|----------|
| Server crash | `reproduce-server-crash.sh`: start → trigger → liveness check |
| Go test | `reproduce-go-test-inline.sh` / `reproduce-go-test-inject.sh`: adapt the fix's test into `TestDDBenchOracle*`, run with `go test -json` |
| Race condition | `reproduce-go-race-loop.sh`: loop N times with `-race` |
| Deadlock | Loop N times under `timeout` → a hang is FAIL |
| Data correctness | `reproduce-server-correctness.sh`: baseline → trigger → read back → assert |
| JVM / Erlang / Rust test | `reproduce.sh` plus the verdict helpers of a real case (see templates/README.md) |

### 2.6 Write README.md

Fill in `case-README.md` (copied as `README.md`) with:
- Project name, issue number, and short title
- Bug category (Crash, Data race, Deadlock, etc.)
- 2-3 sentence summary in observable terms
- Expected PASS/FAIL behavior

### 2.7 Write solution.md and gold.patch

Place both in `cases-solution/<case-name>/`. `solution.md` starts with `# Solution: <Project> #<issue>` and the header list (`- **Issue:**`, `- **Fix commit:**`, `- **Gold patch:**`), then:
- **Fix locus** — name the component/subsystem and list the files changed (this enables evaluation of diagnostic accuracy)
- Root cause explanation (code-level)
- **Diagnosis chain** — document the reasoning path from symptom to root cause, explicitly noting where runtime evidence (logs, crash output, cluster state) and code reasoning (invariant violations, control flow analysis) each contribute. This serves as the evaluation rubric.
- Fix description

`gold.patch` is the source-only part of the upstream fix, as a unified diff relative to the
repository root. The case repository does not contain the fix commit, so take the diff from
the project cache volume, keeping production sources and leaving out tests, docs and
changelogs:

```bash
PROJECT=<project>; FIX=<fix_commit>
docker run --rm -v "bug-bench-$PROJECT-cache:/cache:ro" "bug-bench/$PROJECT" bash -c \
  "git config --global --add safe.directory '*'; git --git-dir=/cache/repo.git diff $FIX~1 $FIX -- <source paths>" \
  > "cases-solution/<case-name>/gold.patch"
grep '^diff --git' "cases-solution/<case-name>/gold.patch"   # review the file list
```

The project cache is cloned once and never updated by bench.sh. If it predates the fix (or
setup cannot resolve `buggy_commit`), update it first:
`docker run --rm -v "bug-bench-$PROJECT-cache:/cache" "bug-bench/$PROJECT" git --git-dir=/cache/repo.git fetch origin '+refs/heads/*:refs/heads/*'`.
For a backport or a hand-written fix, say so in `fix_commit_note`.
The patch must apply with `git apply` at `buggy_commit` and must not add third-party
dependencies (scoring builds offline).

### 2.8 Create devcontainer.json

Generated by the scaffolding commands from `templates/devcontainer.json` (case name, project,
`CASE_UID`); fill in `TODO_EXTENSIONS` with the language's VS Code extensions. Alternatively
regenerate every config with `python3 scripts/generate_devcontainers.py`.

### Authoring context/

`context/` is optional debug context for the context-augmented condition: with `--context`
it is mounted read-only at `/workspace/src/context`; otherwise the agent never sees it. Write it
with the `.claude/skills/debug-context` skill (`/debug-context <case>`) and check it with
`.claude/skills/sanitize` (`/sanitize <case>`).

`context/` is **observational**: what a developer could gather at the buggy commit *before
knowing the fix*.
- Allowed: output of tests and CLIs that exist at the buggy commit, server logs, stack traces, sanitizer and race-detector reports, gdb backtraces, thread/goroutine dumps, metrics, and code-reading notes that describe what the code does (real `grep -n` / `sed -n` output plus at most a question about which area is worth a closer look, as `/debug-context` describes).
- Forbidden: any diagnosis, root cause, or fix direction; links to or numbers of the upstream issue, PR or fix commit; anything from the oracle (`reproduce.sh` output, PASS/FAIL verdicts, injected `DDBenchOracle*` tests, oracle thresholds, windows or trigger parameters); interpretation added to raw tool output.
- Every runtime file names the command that produced it (`Obtained by running ...`), run inside `./bench.sh shell <case>` from `/workspace/src` against a clean (`./bench.sh reset`) worktree, never through bench.sh or `/bench`.
- `symptom.md` never refers to `context/`: it is the same in both conditions.

---

## Phase 3: Docker Support

### 3.1 Check if a project Dockerfile exists

```bash
ls docker/<project>.Dockerfile
```

If it exists, skip to Phase 4.

### 3.2 Preflight: validate build requirements BEFORE writing Dockerfiles

Do this research step first to avoid late-stage toolchain failures:

```bash
# On the buggy commit, check what the project needs:
# 1. Read the project's build docs (CMakeLists.txt, Makefile, go.mod, pom.xml, Cargo.toml, ...)
# 2. Identify compiler version requirements, specific library versions
# 3. Check for known toolchain incompatibilities at this commit
# 4. Estimate build time and resource requirements
```

**Common traps to check for:**
- Does the project pin a specific compiler version (e.g. a minimum clang or GCC release)?
- Does a C++ project also need a Rust or Go toolchain for some components?
- Are there git submodules that pull large dependencies? Check total clone size.
- How many CPUs and how much RAM does the build need? Set `docker.num_cpus` accordingly.
- Can every dependency be resolved once and then used offline (vendored or cacheable)?

Only proceed to writing the Dockerfile once you've confirmed the toolchain is viable.

### 3.3 Determine the base image

- C/C++ projects → `FROM bug-bench/base-cpp`
- Go projects → `FROM bug-bench/base-go`
- Other languages → a standalone Dockerfile from a digest-pinned upstream image, like the Java, Rust and Erlang projects (see [docker-containment.md](docker-containment.md#adding-docker-support-for-a-new-project))

### 3.4 Create the project Dockerfile

Write `docker/<project>.Dockerfile`, installing only the dependencies needed to compile the project and run the oracle. Test it:

```bash
./bench.sh build-images <project>          # builds base images first if needed
docker run --rm -it bug-bench/<project> bash
```

**Dockerfile rules:**
- Use `--no-install-recommends` to minimize image size
- Clean apt cache (`rm -rf /var/lib/apt/lists/*`) after install
- Pin tool versions where the project requires them (don't rely on `apt-get` latest), and pin external base images by digest
- Do NOT bake source code, build outputs or dependency caches into the image
- Test that the build works as both root (scoring) and the non-root `bench` user (agents)

---

## Phase 4: Validation

### 4.1 Setup and the buggy verdict

```bash
./bench.sh setup <case-name>
# The warm-up should print: "Warm-up: the oracle reports FAIL on the buggy code, as expected."
./bench.sh reproduce <case-name>
# Expected: exit 1, output ending in "FAIL: Bug is present ..."
```

Read the whole output, not just the verdict: an error in the trigger path (`command not
found`, `Permission denied`, `Connection refused`) means the FAIL is meaningless.

### 4.2 Iterating on reproduce.sh

```bash
./bench.sh shell <case-name>
bash /bench/reproduce.sh     # the case directory is bind-mounted live: host edits apply at once
```

The shell has network access; scoring does not. Always confirm with `./bench.sh reproduce`,
and `./bench.sh reset <case-name>` after experiments that modified the worktree. The
warm-up runs only while the dependency cache is unwarmed: if the oracle now needs
dependencies it never fetched, drop the cache and set up again, which re-warms it:

```bash
./bench.sh stop <case-name>
docker volume rm "$(./bench.sh info <case-name> deps_volume)"
./bench.sh setup <case-name>
```

### 4.3 Oracle soundness

```bash
./bench.sh validate-oracle <case-name> --runs 3 --json /tmp/<case-name>.validate.json
```

It resets the worktree, runs the oracle N times on the buggy code (each run must FAIL),
applies `cases-solution/<case-name>/gold.patch`, runs it N times (each must PASS), and resets
again. Status: `SOUND` (exit 0), `UNSOUND` or `FLAKY` (exit 1), `ERROR` (exit 2: an ERROR run,
a failed reset, or a gold patch that does not apply), `NO-GOLD` (exit 3). Use `--runs 3` or more
for timing- or race-based oracles. Keep the `--json` result: it goes into the release record
(`docs/oracle-validation.md` and `registry/oracle_validation.json`, generated by
`scripts/oracle_validation_report.py`). `/verify-oracle`
adds the semantic checks (negative control, trigger confirmation, fix-specific anti-patterns).

To score any other patch the same way: `./bench.sh eval <case-name> --patch fix.diff [--runs N] [--json out.json]`.

### 4.4 Idempotency check

```bash
# Run setup twice — the second run should be fast (repository exists, cache already warm)
./bench.sh setup <case-name>
./bench.sh setup <case-name>

# Run reproduce twice — both should give the same result
./bench.sh reproduce <case-name>
./bench.sh reproduce <case-name>
```

### 4.5 Clean slate test

```bash
./bench.sh clean <case-name>
./bench.sh setup <case-name>
./bench.sh reproduce <case-name>
```

---

## Phase 5: Integration

### 5.1 Update index.md

Add a row to the table in `index.md`:

```markdown
| <rank> | <Project> | <issue-url> | <Bug description> | `<case-name>` |
```

Rank by bug difficulty/category (crashes first, then data issues, then races, etc.).

### 5.2 Update project tables

If this case introduces a new project, update the "Covered projects" tables (`CLAUDE.md`, the repository `README.md`) with the project name, language, and case count, and keep the total case counts in sync.

### 5.3 Final review

- All case files present and formatted correctly (no per-case setup script or setup doc)
- solution.md and gold.patch present in cases-solution/
- devcontainer.json present in .devcontainer/
- `./bench.sh validate-oracle <case> --runs 3` reports SOUND
- Docker pipeline produces FAIL on the buggy commit, with no trigger errors in the output (repeated runs)
- Negative control for metric oracles: the scenario without the bug trigger does not FAIL
- `context/` (if any) is observational only: no oracle output, verdicts or parameters, no diagnosis, no upstream links
- `bench.sh reproduce` output ends with exactly `FAIL: ...`, `PASS: ...` or `ERROR: ...`
- No answer leakage in symptom.md, README.md or reproduce.md
- Dual-reasoning requirement met: diagnosis requires both code and runtime evidence
- GitHub issue text does not trivially reveal the fix
