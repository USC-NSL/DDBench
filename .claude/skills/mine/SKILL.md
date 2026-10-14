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

**Pin down the defect semantics before writing anything.** Using the issue body, the fix commit message, and the fix diff, write down:
- **Defect:** what the buggy code does wrong (one sentence, grounded in the diff).
- **Observable effect:** what a user or operator sees.
- **What the fix changes observably:** the behavior that differs between the buggy and fixed builds. The oracle must observe this.
- **Upstream test:** if the PR adds a test, read its assertions. It tells you what the maintainers consider the bug's effect.

Check that the issue's terms match the diff. Don't infer semantics from a title. In kvrocks-3356, "WAL exhaustion" meant the replica's WAL position got pruned while the feed thread was blocked; the case was built as if it meant disk filling up, and the oracle measured the wrong thing. If the fix diff doesn't change what you plan to measure, rethink before scaffolding.

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
8. Do **not** put oracle output in `context/`. Debug context comes only from `/debug-context` (a developer investigating at the buggy commit) or from `/sanitize` Tier-2 extraction. It never comes from `reproduce.sh` output, verdicts, or oracle parameters.

**Oracle design rules (reproduce.sh):**
- **Observe the behavior the fix changes** (Phase 1), not a side quantity the workload produces anyway. Disk size, memory, and latency thresholds are a last resort and need a negative control (`/verify-oracle` Step 2.6).
- **Three outcomes:** `FAIL:` (exit 1), `PASS:` (exit 0), `ERROR:` (exit 2). Never let a broken trigger reach the verdict. ERROR is only for failures of the oracle's own machinery, independent of the code under test (missing tool, trigger not established, injected oracle test doesn't compile, `-run` matches nothing). Anything the code under test does wrong (doesn't build, doesn't start, never reaches the baseline state, crashes) is FAIL. Scoring counts every non-zero exit as FAIL; ERROR is a diagnostic for case authors, never an exemption.
- **Assert every trigger took effect,** not just that the command ran: process stopped, connection stalled, partition dropping, node down. Don't use `2>/dev/null` or `|| true` on trigger steps.
- **No `sudo`.** The images ship none, and `bench.sh reproduce` already runs as root. Prefer process-level faults (`SIGSTOP`/`SIGCONT`, killing a node, a pausable TCP proxy) over `iptables`/`tc`: they need no extra capabilities and target exactly one peer. If you must filter packets, match the real connection: client-initiated connections (e.g. replica→master) use ephemeral ports.
- **Accept alternative fixes:** no config options, commands, or log strings that exist only in the fix. Make detection windows generous (e.g. 90s when upstream uses a 30s timeout), so any reasonable fix passes.
- **Case text stays observational.** Agents never see `/bench` (`bench.sh agent` doesn't mount it), but humans in shells/devcontainers do, and any future leak would expose it. As defense in depth, reproduce.sh, its output, and the case `.md` files describe what was observed ("replica still attached after 90s"), not the mechanism ("thread blocked in write() with no timeout").
- **Use bounded client calls** (`timeout 5 redis-cli ...`), so a hung server yields a verdict instead of a hung oracle. Treat a failed status query as unknown, never as "healthy" or "detached".

---

## Phase 4: Verify case (with diagnose-case loop)

```
for attempt in 1..3:
    ./bench.sh setup <case-name>
    if SETUP_FAIL → /diagnose-case --phase setup → fix → continue

    ./bench.sh reproduce <case-name>
    if PASS on buggy → /diagnose-case --phase reproduce (Category C) → fix → continue
    if error (no FAIL:) → /diagnose-case --phase reproduce (Category B) → fix → continue
    if FAIL: present → read the full output (not just the verdict):
        any trigger-path error (command not found, permission denied, connection refused)
            → Category B → fix → continue
        otherwise → VERIFIED → break
```

Abort after 3 failed attempts. Report last failure category.

A FAIL here is necessary but not sufficient. It only shows the oracle *can* FAIL. Phase 5 shows it FAILs *because of the bug*.

---

## Phase 5: Verify oracle (with diagnose-case loop)

Run `/verify-oracle <case-name>` in full. In particular:
- **Step 2.6 validity checks:** semantic check against the fix diff, negative control for metric oracles, trigger confirmed in-script.
- **Step 3:** the fix commit (from the project cache volume, fetched from upstream if missing) is applied to a **scratch copy** of the case volume. The tree hash is proven equal to `<fix>^{tree}` and built clean. The fix commit is not in the case volume, so `git checkout <fix-commit>` there fails.
- **Step 3.5:** repeated runs in both directions.

```
for attempt in 1..3:
    /verify-oracle <case-name>
    if SOUND: → break
    if FAIL-for-wrong-reason / control FAILs → redesign oracle (Phase 3 rules) → re-run Phase 4 → continue
    if fixed FAILs → /diagnose-case --phase oracle (Category D) → fix → re-verify Direction 1 → continue
```

Abort after 3 failed attempts.

---

## Phase 6: Sanitize and integrate

1. Run `/sanitize <case-name>` — check symptom.md for leakage against solution.md
   - Agents don't get `/bench`, but as defense in depth apply the same leak check to `README.md`, `reproduce.md`, `verification.md`, comments in `reproduce.sh`, and the oracle's printed messages. They may describe the scenario and what is observed, but not the root-cause mechanism or the fix.
   - `context/` must contain no oracle information: no `reproduce.sh` output, no PASS/FAIL verdicts, and no oracle trigger parameters, thresholds, or windows.
2. Follow `mining-protocol/authoring-guide.md` Phase 5: update `index.md`, update `CLAUDE.md` if new project
3. Final report (single case) or progress update (campaign mode)

---

## Operational Notes

- **SYMPTOM.md lives in the case volume too.** `bench.sh setup` copies `symptom.md` into the worktree as `SYMPTOM.md`, and `reset` preserves that copy. After editing `symptom.md` on an existing case, refresh the copy (re-run setup, or copy it into the volume).
- **`bench.sh reproduce` rebuilds first** (its build step plus the worktree's `REBUILD.sh`; for CMake projects that's a reconfigure, which can take minutes). While iterating on reproduce.sh, run it in a plain `docker run` against the case volume, then do the final check through `bench.sh reproduce`.
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
