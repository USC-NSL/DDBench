# /mine — End-to-End Bug Case Mining

Mine benchmark cases. Accepts a PR URL, issue URL, or natural language — from a single targeted case to a multi-repo mining campaign. Orchestrates analysis, evaluation, scaffolding, and iterative verification with built-in failure diagnosis.

## Usage

```
/mine <PR-URL>
/mine <ISSUE-URL>
/mine <natural language — single case or campaign>
/mine <any of the above> --dry-run
/mine <any of the above> --slug <slug>
```

**Examples:**
```
# Single case from PR or issue
/mine https://github.com/etcd-io/etcd/pull/20281
/mine https://github.com/apache/kvrocks/issues/2520

# Single case from natural language
/mine find a race condition bug in nats-server's JetStream consumer path

# Campaign — mine multiple cases with strategy
/mine mine 8-12 cases across etcd, raft, nats, kvrocks. Prioritize replication
      consistency and leader election bugs. Balance across repos.
```

---

## Phase 0: Input Resolution

Determine the **mode** (single vs campaign) and resolve to concrete candidates.

### Path A: PR URL → single case

Input matches `https://github.com/<org>/<repo>/pull/<number>`.

```bash
gh pr view <URL> --json state,mergeCommit,title,body,files,additions,deletions
```

If `state != MERGED` → warn and abort. Extract `mergeCommit.oid`. Proceed to Phase 1.

### Path B: Issue URL → single case

Input matches `https://github.com/<org>/<repo>/issues/<number>`.

```bash
gh issue view <URL> --json title,body,state,comments
gh api repos/<org>/<repo>/issues/<number>/timeline --paginate
```

Find linked/closing PRs. If one merged fix PR → use it (Path A). If multiple → pick most focused. If none → abort.

### Path C: Natural language → single case

Input is free-form but describes **one** case (e.g., "find a race condition in nats").

Parse for project hints, bug type, component, recency. Search:

```bash
gh search issues --repo <org>/<repo> --label bug --state closed \
  --sort updated -- "<keywords>"
```

Present top 3-5 candidates. After user selects → Path A.

### Path D: Natural language → campaign (multiple cases)

Input describes a **mining campaign** with any of these signals:
- A target count ("mine 8-12 cases", "find 5 more bugs")
- Multiple repos listed ("across etcd, raft, nats, kvrocks")
- Balance/distribution constraints ("balance across repos", "don't let any repo dominate")
- Priority ordering ("prioritize etcd, then consul")
- Bug type preferences ("prefer replication, leader election, snapshot bugs")

When detected, run the **Campaign Planning** sub-phase before any execution.

#### D.1: Parse the campaign strategy

Extract a structured plan from the natural language:

```yaml
campaign:
  target_count: 8-12          # how many cases to produce
  repos:                       # ordered by priority
    - org: etcd-io, repo: etcd, priority: 1, max_cases: 3
    - org: hashicorp, repo: raft, priority: 1, max_cases: 3
    - org: nats-io, repo: nats-server, priority: 1, max_cases: 3
    - org: apache, repo: kvrocks, priority: 1, max_cases: 3
    - org: hashicorp, repo: consul, priority: 2, max_cases: 2
    - org: rabbitmq, repo: rabbitmq-server, priority: 3, max_cases: 1
  bug_types:                   # preferred categories
    - replication consistency
    - snapshot/restore
    - leader election
    - failover/recovery
    - membership change
  balance_rule: "max 3 per repo, aim for 4-6 repos represented"
  exclusions:                  # from user or auto-detected
    - shallow single-node bugs
    - race-detector-only without distributed semantics
    - unreproducible/flaky
    - solvable from issue text alone
```

#### D.2: Survey existing benchmark coverage

```bash
# Count existing cases per project
ls cases/ | cut -d- -f1 | sort | uniq -c | sort -rn
```

Identify which repos are underrepresented vs overrepresented. Factor this into candidate ranking.

#### D.3: Search across repos

For each repo (in priority order), search for candidates matching the bug type preferences:

```bash
gh search issues --repo <org>/<repo> --label bug --state closed \
  --sort updated -- "fix <bug-type-keyword>"
gh search prs --repo <org>/<repo> --state merged \
  -- "fix <bug-type-keyword>"
```

For each candidate, quick-evaluate:
- Has merged fix PR?
- Fix locus size (files changed, lines changed)?
- Already in benchmark? (`ls cases/ | grep <issue#>`)
- Does issue text reveal the fix? (skim title + first paragraph)
- Bug type matches preferences?

#### D.4: Rank and present the campaign plan

Score candidates using:
1. **Balance score**: Higher if the repo is underrepresented in existing benchmark
2. **Type score**: Higher if the bug type matches preferences
3. **Locus score**: Higher if fix is 1-3 files, <50 lines
4. **Reproducibility signal**: Higher if issue describes clear repro steps or PR includes a test
5. **Distributed depth**: Higher if bug involves multi-node interaction, not single-node

Present the plan:

```
=== Mining Campaign Plan ===
Target: 10 cases across 5 repos

Existing coverage: dragonfly(14), nats(6), kvrocks(6), etcd(4), raft(4)
Strategy: Prioritize etcd, raft, nats, kvrocks for depth; add consul for breadth

| # | Repo | Issue | Title | Type | Locus | Score |
|---|------|-------|-------|------|-------|-------|
| 1 | etcd | #19899 | watch progress notify stalls after compaction | data loss | 2 files | 92 |
| 2 | raft | #540 | snapshot restore drops uncommitted entries | snapshot | 1 file | 90 |
| 3 | nats | #7650 | consumer filter lost after raft snapshot | data loss | 3 files | 88 |
| 4 | consul | #21045 | anti-entropy sync drops during leader change | replication | 2 files | 85 |
| ...

Proceed with this plan? (yes / edit / add <url> / drop <#>)
```

User can:
- **yes**: execute all in order
- **edit**: modify the plan (add/remove/reorder)
- **add `<url>`**: insert a specific PR/issue into the queue
- **drop `<#>`**: remove a candidate

#### D.5: Execute sequentially

Process each candidate through Phases 1-6. Between cases:

```
[3/10] Mining consul-21045-antientropy-leader-change...
  Phase 1: Analyzing PR #21046... ✓
  Phase 2: Selection criteria 9/9 PASS
  Phase 3: Scaffolding... ✓
  Phase 4: Verify case... VERIFIED (attempt 1/3)
  Phase 5: Verify oracle... SOUND (attempt 1/3)
  Phase 6: Sanitize... CLEAN
  → COMPLETE

Campaign progress: 3/10 complete, 0 failed, 7 remaining
Balance: etcd(2), raft(1), nats(0), consul(0) — next: nats
```

**Balance enforcement**: After each successful case, re-check repo distribution. If a repo has hit its `max_cases`, skip remaining candidates from that repo and pull from the next priority level.

**Failure handling**: If a candidate fails after 3 diagnose-case attempts, log it and continue to the next. Don't abort the campaign.

#### D.6: Campaign report

```
=== Campaign Report ===
Target: 10 cases  |  Completed: 8  |  Failed: 2  |  Skipped: 1

| # | Case | Repo | Type | Status |
|---|------|------|------|--------|
| 1 | etcd-19899-watch-compaction-stall | etcd | data loss | COMPLETE |
| 2 | raft-540-snapshot-uncommitted | raft | snapshot | COMPLETE |
| 3 | nats-7650-consumer-filter-snapshot | nats | data loss | COMPLETE |
| 4 | consul-21045-antientropy-leader | consul | replication | ORACLE_FAIL |
| ...

Balance achieved: etcd(3), raft(2), nats(2), kvrocks(1), consul(0)
Failed candidates saved to: mining-campaign-failures.md (for manual review)
```

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
3. Final report (single case) or progress update (campaign mode)

---

## Operational Notes

- **inject_test.go compatibility trap** (most common oracle failure): The test must compile on BOTH buggy and fixed commits. Always read source at the buggy commit before writing.
- **Multi-commit PRs**: Fix may not be the merge commit. Check `gh pr view --json commits`.
- **Go projects without binaries** (e.g., hashicorp/raft): `build.command` and `build.binary` are empty strings.
- **Race cases**: 5+ iterations with `-race`, pre-seed data to widen the window. Target >90% aggregate detection.
- **New repos in campaigns**: When a repo is new to the benchmark (no existing Dockerfile), the first case from that repo will take significantly longer due to Dockerfile creation and initial build.

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
- `/mine-batch` — file-based batch processing (alternative to campaign mode)
