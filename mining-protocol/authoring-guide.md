# Authoring Guide

Step-by-step walkthrough for adding a new case to the benchmark.

---

## Phase 1: Bug Selection and Validation

### 1.1 Identify a candidate bug

Find a GitHub issue in a distributed system project that:
- Has a merged fix (closed issue with linked PR)
- Describes a concrete, reproducible failure
- Falls within the [selection criteria](selection-criteria.md)

### 1.2 Locate the fix commit

```bash
# From the PR, find the merge commit or squash commit
git log --oneline --all | grep "<PR-number>"
# Or check the PR's "Commits" tab on GitHub
```

Record the fix commit hash. The buggy commit is `<fix-commit>~1`.

Then write down, from the issue, the fix commit message, and the diff: the **defect**, its **observable effect**, and **what the fix changes observably**. If the PR adds a test, read its assertions. Check that the issue's terms match the diff (kvrocks-3356's "WAL exhaustion" meant WAL pruned under a blocked replica, not disk full). The oracle in 2.7 must observe what the fix changes.

### 1.3 Verify local reproduction

Before writing any case files, manually reproduce the bug:

```bash
git clone <repo>
cd <repo>
git checkout <fix-commit>~1
# Build and trigger the bug following the issue description
```

If you cannot reproduce reliably, the bug is not suitable.

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

### 2.1 Create the case directory

```bash
# Naming: <project>-<issue#>-<2-4-word-slug>
CASE_NAME="<project>-<issue#>-<slug>"
cp -r mining-protocol/templates/ "cases/$CASE_NAME/"
mkdir -p "cases-solution/$CASE_NAME/"
mkdir -p ".devcontainer/$CASE_NAME/"
```

### 2.2 Fill in case.yaml

Start here — this drives all automation. See [case-anatomy.md](case-anatomy.md) for the schema.

Key decisions:
- **build.command**: Test locally inside the Docker container. Multi-step builds use YAML block scalar (`|`)
- **build.binary**: Path relative to worktree root. Use `""` for test-only cases (Go libraries)
- **docker.caps**: Only add capabilities that are actually required. Test without them first

### 2.3 Write symptom.md

Describe the bug as someone encountering it for the first time would. Do NOT reveal the root cause. This file is the starting point for agents and human debuggers during evaluation.

Good: "The server crashes with SIGABRT when MONITOR is called twice inside MULTI/EXEC."
Bad: "The ChangeMonitor function is not idempotent." (this reveals the fix)

### 2.4 Write reproduce.md

Document the manual reproduction steps you validated in Phase 1. Include exact commands, ports, and expected output.

### 2.5 Write verification.md

Extract the core verification logic into a bash snippet. Define precise PASS/FAIL conditions.

### 2.6 Write setup.sh

Copy the Docker preamble from the template verbatim. Then implement the host fallback:
1. Install build dependencies via `apt-get`
2. Clone the repo (with `--recurse-submodules` if needed)
3. Checkout the buggy commit
4. Build the project
5. Make the script idempotent (skip clone/build if artifacts exist)

### 2.7 Write reproduce.sh

Copy the Docker preamble from the template verbatim. Then implement the host fallback:
1. Verify binary exists
2. Clean up from previous runs
3. Start the service (if server-based)
4. Trigger the bug, then **confirm the trigger took effect** (otherwise `ERROR: ...`, exit 2)
5. Check the outcome: observe the behavior the fix changes (1.2), using bounded client calls (`timeout 5 ...`)
6. Print `PASS: ...` or `FAIL: ...` and exit with 0 or 1; an inconclusive path prints `ERROR: ...` and exits 2, but only when the oracle itself failed. If the code under test fails to build or start, that is FAIL.

Agents never see `/bench`, but as defense in depth, reproduce.sh comments and messages describe what is observed, not the root-cause mechanism. Don't use options, commands, or log strings that exist only in the fix, and make detection windows generous so alternative fixes pass.

Choose the right reproduction strategy for the bug type:

| Bug Type | Template Pattern |
|----------|-----------------|
| Server crash | Start → trigger → `kill -0 $PID` check |
| Go test | Extract test from fix → `go test -run <TestName>` |
| Race condition | Loop N times with `-race` flag → count failures |
| Deadlock | Loop N times with `timeout` → count hangs |
| Data correctness | Write → mutate → read → assert |

### 2.8 Write setup.md

Document the build process for human readers. Include project info, clone commands, build commands, and deployment steps for clustered services.

### 2.9 Write README.md

Fill in the template with:
- Project name, issue number, and short title
- Bug category (Crash, Data race, Deadlock, etc.)
- 2-3 sentence summary
- Prerequisites list
- Expected PASS/FAIL behavior

### 2.10 Write solution.md

Place in `cases-solution/<case-name>/solution.md`. Include:
- Link to the fix PR and commit
- **Fix locus** — name the component/subsystem and list the files changed (this enables evaluation of diagnostic accuracy)
- Root cause explanation (code-level)
- **Diagnosis chain** — document the reasoning path from symptom to root cause, explicitly noting where runtime evidence (logs, crash output, cluster state) and code reasoning (invariant violations, control flow analysis) each contribute. This serves as the evaluation rubric.
- Fix description
- How to apply the fix

### 2.11 Create devcontainer.json

Place in `.devcontainer/<case-name>/devcontainer.json`. Use the template and fill in project name, case name, and language-appropriate VS Code extensions.

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
# 1. Read the project's build docs (CMakeLists.txt, Makefile, go.mod, etc.)
# 2. Identify compiler version requirements, specific library versions
# 3. Check for known toolchain incompatibilities at this commit
# 4. Estimate build time and resource requirements
```

**Common traps to check for:**
- Does the project pin a specific compiler version? (e.g., ClickHouse requires clang-23)
- Does the project need Rust toolchain in addition to C++? (e.g., ClickHouse with Rust nightly)
- Are there git submodules that pull large dependencies? Check total clone size.
- Does the build require more than 4GB RAM? Flag this in `case.yaml` min_cpus.

Only proceed to writing the Dockerfile once you've confirmed the toolchain is viable.

### 3.3 Determine the base image

- C/C++ projects → `FROM bug-bench/base-cpp`
- Go projects → `FROM bug-bench/base-go`
- New language → create a new base image first (see [docker-containment.md](docker-containment.md))

### 3.4 Create the project Dockerfile

```bash
# docker/<project>.Dockerfile
```

Install only the dependencies needed to compile the project. Test by building inside the container:

```bash
# Build the base image first
docker build -t bug-bench/base-cpp -f docker/base-cpp.Dockerfile docker/
# Build the project image
docker build -t bug-bench/<project> -f docker/<project>.Dockerfile docker/
# Test: start container and try to build
docker run --rm -it bug-bench/<project> bash
```

**Dockerfile rules:**
- Use `--no-install-recommends` to minimize image size
- Clean apt cache (`rm -rf /var/lib/apt/lists/*`) after install
- Pin tool versions where the project requires them (don't rely on `apt-get` latest)
- Do NOT bake source code or run builds — source is mounted at runtime
- Test that the build works as both root and non-root user

---

## Phase 4: Validation

### 4.1 Docker mode validation

```bash
# Full pipeline
./bench.sh setup <case-name>
./bench.sh reproduce <case-name>
# Expected output: "FAIL: Bug is present ..."

# Verify the fix works: /verify-oracle <case-name>
# The fix commit is NOT in the case volume (history is truncated to the buggy
# commit), so `git checkout <fix-commit>` there fails. /verify-oracle Step 3 takes
# the fix from the project cache volume, applies it to a scratch copy of the case
# volume, proves `git write-tree` == <fix>^{tree}, does a clean build, and runs the
# oracle. Expected output: "PASS: Bug is fixed ..." on every repeated run.
```

### 4.2 Host mode validation (if possible)

```bash
cd cases/<case-name>
./setup.sh
./reproduce.sh
# Expected: FAIL
```

### 4.3 Idempotency check

```bash
# Run setup twice — second run should be fast (skip clone/build)
./bench.sh setup <case-name>
./bench.sh setup <case-name>

# Run reproduce twice — both should give same result
./bench.sh reproduce <case-name>
./bench.sh reproduce <case-name>
```

### 4.4 Clean slate test

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

### 5.2 Update CLAUDE.md

If this case introduces a new project, update the "Covered projects" table in `CLAUDE.md` with the new project name, language, and case count.

### 5.3 Final review

- All 8 case files present and formatted correctly
- solution.md present in cases-solution/ with fix locus and diagnosis chain
- devcontainer.json present in .devcontainer/
- Docker pipeline produces FAIL on buggy commit, with no trigger errors in the output (repeated runs)
- Negative control for metric oracles: the scenario without the bug trigger does not FAIL
- PASS on the hash-verified, clean-built fix tree (`/verify-oracle`, repeated runs)
- `context/` contains no oracle information (no reproduce.sh output, verdicts, or oracle parameters)
- `bench.sh reproduce` output ends with exactly `FAIL: ...` or `PASS: ...`
- No answer leakage in symptom.md, reproduce.md, or verification.md
- Dual-reasoning requirement met: diagnosis requires both code and runtime evidence
- GitHub issue text does not trivially reveal the fix
