# /mine — End-to-End Bug Case Mining

Mine a new benchmark case. Accepts natural language, a PR URL, or an issue URL. Orchestrates analysis, evaluation, scaffolding, and iterative verification with built-in failure diagnosis.

## Usage

```
/mine <natural language description>
/mine <PR-URL>
/mine <ISSUE-URL>
/mine <any of the above> --dry-run
/mine <any of the above> --slug <slug>
```

**Examples:**
```
/mine https://github.com/etcd-io/etcd/pull/20281
/mine https://github.com/apache/kvrocks/issues/2520
/mine find a race condition bug in nats-server's JetStream consumer path
/mine look for data loss bugs in kvrocks replication, prefer issues from 2024
/mine https://github.com/hashicorp/raft/pull/581 --slug transfer-write-race
```

---

## Phase 0: Input Resolution

Resolve input into a concrete **fix PR + fix commit**. Three paths converge into Phase 1.

### Path A: PR URL

Input matches `https://github.com/<org>/<repo>/pull/<number>`.

```bash
gh pr view <URL> --json state,mergeCommit,title,body,files,additions,deletions
```

If `state != MERGED` → warn and abort. Extract `mergeCommit.oid`. Proceed to Phase 1.

### Path B: Issue URL

Input matches `https://github.com/<org>/<repo>/issues/<number>`.

```bash
gh issue view <URL> --json title,body,state,comments
gh api repos/<org>/<repo>/issues/<number>/timeline --paginate
```

Find linked/closing PRs. If one merged fix PR → use it (Path A). If multiple → pick most focused. If none → abort.

### Path C: Natural language

Parse input for project hints, bug type, component, recency constraints.

```bash
# Search known project issues
gh search issues --repo <org>/<repo> --label bug --state closed \
  --sort updated -- "<keywords>"
```

Present top 3-5 candidates with one-line summaries:
```
1. nats-io/nats-server#7707 — concurrent map crash in WQ consumer partition
   Fix: PR #7708, 2 files, +15/-3 lines. Type: data race
2. ...
```

After user selects → resolve to PR URL → Path A.

**Auto-selection**: Prefer bugs not already in benchmark, underrepresented types, smaller fix locus, clear repro steps.

---

## Phase 1: Analyze the fix

```bash
gh pr view <PR-URL> --json title,body,mergeCommit,files,additions,deletions,labels,commits
gh pr diff <PR-URL>
```

If PR references an issue (`Fixes #NNN`):
```bash
gh issue view <number> -R <org>/<repo> --json title,body
```

Derive case metadata:
- **project**, **case name** (`<project>-<issue#>-<slug>`), **repo URL**
- **fix commit** (`mergeCommit.oid`), **buggy commit** (`<fix>~1`)
- **language**, **submodules**, **build command**, **binary path**, **bug type**

For build command: check existing `cases/<project>-*/case.yaml` first, then `Makefile` / `CMakeLists.txt` / `go.mod`.

Check deduplication: `ls cases/ | grep <issue-number>`

---

## Phase 2: Evaluate selection criteria

Evaluate all 9 mandatory criteria from `mining-protocol/selection-criteria.md`. For each, produce PASS/FAIL/UNCERTAIN.

**Gate**: Any FAIL → report and abort. UNCERTAIN → proceed with warning.

Apply the three gatekeeping tests from `mining-protocol/authoring-guide.md` Phase 1.4:
1. **Dual-reasoning**: needs both code reading AND runtime evidence?
2. **Fix locus**: can name component + 1-3 files?
3. **Issue text**: does issue reveal the fix?

If `--dry-run` → output evaluation report and stop.

---

## Phase 3: Scaffold case files

Follow `mining-protocol/authoring-guide.md` Phase 2 to create all files. Key inputs from Phase 1.

**Prerequisites check:**
- `docker/<project>.Dockerfile` exists? If not → create per `authoring-guide.md` Phase 3
- Existing cases for this project? → reuse build config from `cases/<project>-*/case.yaml`

**Scaffold decisions:**
1. Write `case.yaml` per `mining-protocol/case-anatomy.md` Section 1
2. Select bug-type-specific reproduce template from `mining-protocol/templates/`:
   - `reproduce-go-test-inline.sh` — Go test embedded as heredoc
   - `reproduce-go-test-inject.sh` — Go test from external inject_test.go + loop
   - `reproduce-go-race-loop.sh` — Go `-race` detector with iteration loop
   - `reproduce-server-crash.sh` — start server → trigger → PID survival check
   - `reproduce-server-correctness.sh` — cluster setup → write/trigger/verify data
3. If Go test injection: write `inject_test.go` using **only APIs at the buggy commit** — read relevant source first
4. Write documentation files per `case-anatomy.md` Sections 2-5
5. Write `solution.md` in `cases-solution/` with fix locus + diagnosis chain
6. Write `devcontainer.json` per template
7. `chmod +x` both scripts

---

## Phase 4: Verify case (with diagnose-case loop)

```
for attempt in 1..3:
    ./bench.sh setup <case-name>
    if SETUP_FAIL → /diagnose-case --phase setup → fix → continue

    ./bench.sh reproduce <case-name>
    if PASS on buggy → /diagnose-case --phase reproduce (Category C) → fix → continue
    if error (no FAIL:) → /diagnose-case --phase reproduce (Category B) → fix → continue
    if FAIL: present → VERIFIED → break
```

Abort after 3 failed attempts. Report last failure category.

---

## Phase 5: Verify oracle (with diagnose-case loop)

```
Read fix commit from solution.md, build command from case.yaml

for attempt in 1..3:
    docker run --rm ... bash -c '
      git checkout <fix-commit> &&
      [git submodule update --init --recursive] &&
      [<build-command>] &&
      bash /bench/reproduce.sh'

    if PASS: → SOUND → break
    if FAIL: → /diagnose-case --phase oracle (Category D) → fix
              → bench.sh reset → re-verify Direction 1 → continue
```

After success: `./bench.sh reset <case-name>`

Abort after 3 failed attempts.

---

## Phase 6: Sanitize and integrate

1. Run `/sanitize <case-name>` — check symptom.md for leakage against solution.md
2. Follow `mining-protocol/authoring-guide.md` Phase 5: update `index.md`, update `CLAUDE.md` if new project
3. Final report:

```
=== Mining Report: <case-name> ===
Source: <PR-URL | issue-URL | "natural language search">
Fix Commit: <hash>  |  Buggy Commit: <hash>~1
Selection: 9/9 PASS
Verify: VERIFIED (attempt N/3)  |  Oracle: SOUND (attempt N/3)
Sanitize: CLEAN
Files: cases/<case-name>/ (8) + cases-solution/ + .devcontainer/
Status: COMPLETE
```

---

## Operational Notes

- **inject_test.go compatibility trap** (most common oracle failure): The test must compile on BOTH buggy and fixed commits. Always read source at the buggy commit before writing.
- **Multi-commit PRs**: Fix may not be the merge commit. Check `gh pr view --json commits`.
- **Go projects without binaries** (e.g., hashicorp/raft): `build.command` and `build.binary` are empty strings.
- **Race cases**: 5+ iterations with `-race`, pre-seed data to widen the window. Target >90% aggregate detection.

## References

- `mining-protocol/selection-criteria.md` — 9 mandatory criteria
- `mining-protocol/authoring-guide.md` — 5-phase authoring walkthrough
- `mining-protocol/case-anatomy.md` — file formats and conventions
- `mining-protocol/checklist.md` — pre-merge validation
- `/diagnose-case` — failure taxonomy (Categories A-D) used in Phases 4-5
- `/verify-cases` — batch case verification
- `/verify-oracle` — oracle soundness check
- `/sanitize` — symptom leakage scanner
- `/newcase` — interactive scaffolder (alternative to Phase 3)
- `/mine-batch` — batch processing wrapper for multiple candidates
