# /sanitize — Symptom File Leakage Scanner

Scan symptom files for information leakage — both lexical (specific terms from the solution) and semantic (descriptions that reveal the root cause, diagnosis, or fix strategy without naming exact identifiers). Triage information into three tiers, extract runtime context into a separate `context/` directory, and redact fix-revealing content entirely.

## Usage

```
/sanitize              # scan all cases
/sanitize <case-name>  # scan a specific case
```

## Three-Tier Information Model

All information about a bug falls into exactly one of these tiers:

```
┌─────────────────────────────────────────────────────────────┐
│  Tier 1: symptom.md — What an operator SEES                │
│  Written by someone who only ran the software.              │
│  Crash/hang/wrong output, user-facing errors, CLI output.   │
│  The developer's FIRST contact with the problem.            │
├─────────────────────────────────────────────────────────────┤
│  Tier 2: context/ — What a developer GATHERS               │
│  Obtained by running the system with standard tools         │
│  (logs, debugger, strace, tcpdump, metrics dashboard).      │
│  Helps narrow investigation WITHOUT pinpointing the fix.    │
├─────────────────────────────────────────────────────────────┤
│  Tier 3: REDACTED — What requires reading source code       │
│  Root cause, fix location, internal mechanism, regression    │
│  provenance. Goes NOWHERE — not in symptom, not in context. │
└─────────────────────────────────────────────────────────────┘
```

### Decision heuristic: Where does this information go?

For each piece of information in a symptom file, ask these questions in order:

1. **Could an operator observe this without any tools beyond the application itself?**
   (crash message, wrong CLI output, missing data, timeout)
   → **Tier 1: symptom.md**

2. **Could a developer obtain this using standard runtime tools, WITHOUT reading the project's source code?**
   (stack trace, log output, goroutine dump, strace, core dump backtraces, metrics, config state, protocol-level network captures)
   → **Tier 2: context/** — but ONLY if it doesn't reveal the fix (see debug-context anti-patterns below)

3. **Would you need to read the source code to know this?**
   (which function is wrong, which data structure has a gap, which prior commit introduced it, what the fix should do)
   → **Tier 3: REDACT entirely**

### The Fresh Developer Test

Imagine a developer who just got assigned this bug. They know ONLY what an external user or operator could observe:
- **What went wrong** (crash, missing data, timeout, wrong output)
- **How to trigger it** (the reproduction steps)
- **Which version** is affected

They do NOT know:
- Which internal data structure, function, or code path is involved
- Which prior change or commit introduced the regression
- The causal chain inside the code (why the bug happens mechanically)
- Which subsystem, module, or component to investigate
- What the fix looks like

Every sentence in `symptom.md` must pass this test: **"Could this sentence have been written by someone who only ran the software and observed the failure, without ever reading the source code?"** If not, it either moves to debug context (Tier 2) or gets redacted (Tier 3).

## Procedure

### Step 1: Build the reference set (lexical)

For each case (or the specified case):
1. Read `cases-solution/<case-name>/solution.md`
2. Extract:
   - Function and method names mentioned in "Root cause", "Fix description", and "Diagnosis chain"
   - Variable, struct field, and constant names
   - File paths listed in "Fix locus" → "Files"
   - The component name from "Fix locus" → "Component"
   - PR numbers and commit hashes from "Fix"
   - Internal data structure names (e.g., `committedLog`, `pendingOffsets`, `HandleFactory`)
   - Prior issue/PR references mentioned as regression source (e.g., "ZOOKEEPER-4394")

Store these as the **prohibited terms** for that case.

### Step 2: Lexical scan

For each case, read `cases/<case-name>/symptom.md` and check for:

| Check | How |
|-------|-----|
| Function/method names from fix | Grep for each extracted name (case-sensitive) |
| Variable/field names from fix | Grep for each extracted name |
| Internal data structure names | Grep for struct/class/field names from the fix that are not part of the public API or CLI |
| File paths from fix | Grep for directory or filename fragments |
| Internal constants/magic numbers | Grep for hex values, error codes, or constants from the fix diff |
| Fix strategy descriptions | Look for phrases like "make X idempotent", "add synchronization", "check for null", "handle the case where" |
| Root cause mechanism | Look for causal language pointing to code ("the function fails to", "X is called after Y", "the field is not initialized") |
| Error messages from source only | Compare error strings in symptom against user-facing error strings (OK) vs source-only strings (leak) |
| PR/commit/issue references | Grep for PR numbers, commit hashes, and prior issue IDs cited as regression sources |

### Step 3: Semantic scan

This step catches leakage that passes the lexical scan — information that reveals the diagnosis through description rather than exact terms.

For each sentence in `symptom.md`, apply these semantic checks:

#### 3a. Internal mechanism disclosure

Flag any sentence that describes **how the bug works internally** rather than **what the user sees**.

| Leaks (describes internals) | Clean (describes observation) |
|---|---|
| "the follower's in-memory log has a gap" | "previously committed data is not found on the new leader" |
| "the callback is never invoked, leaving stale state" | "after the error, subsequent operations return incorrect results" |
| "the function uses a variant that does not populate X" | "data written before the failover is missing" |
| "the fencing message arrives after the recovery read" | "the recovered ledger contains fewer entries than expected" |

**Test:** Does the sentence require reading source code to write? If yes → LEAK.

#### 3b. Regression provenance

Flag any reference to a specific prior change, issue, or PR that introduced the bug.

| Leaks | Clean |
|---|---|
| "regression introduced by ZOOKEEPER-4394" | "only affects version 3.9.3 and later" |
| "caused by the fix for issue #1234" | "the behavior changed between v2.1 and v2.2" |
| "after commit abc123 changed the sync path" | "this was not observed in earlier releases" |

**Test:** Does it tell the agent which prior change to `git log --grep` or diff against? If yes → LEAK.

#### 3c. Subsystem / code-path narrowing

Flag naming of internal subsystems, protocol phases, or code paths that are not visible in user-facing behavior, CLI output, or error messages.

| Leaks | Clean |
|---|---|
| "during the SYNCHRONIZATION phase" | "after the node rejoins the cluster" |
| "in the DIFF sync path" | "when a stale node catches up" |
| "the pre_vote state interacts with candidate state" | "the cluster cycles through elections without electing a leader" |
| "the `appendForGroup` call throws instead of using callback" | "the operation fails silently" |

**Test:** Could you identify this subsystem/phase name only by reading source code? If yes → LEAK. Exception: terms that appear in user-facing logs, CLI output, or official documentation are OK.

#### 3d. Fix-direction hints

Flag sentences that implicitly describe what the fix should do.

| Leaks | Clean |
|---|---|
| "the variant does not populate the committed log" | "committed data disappears" |
| "the epoch is persisted before the transactions" | "a restarted node can be elected leader despite missing data" |
| "pending offsets are not cleaned up on exception" | "after a storage error, the coordinator returns stale offsets" |

**Test:** If an agent reads this sentence, does it know what code to change without further investigation? If yes → LEAK.

#### 3e. Diagnostic-equivalence test

Read the symptom file as a whole and compare it against the "Root cause" and "Diagnosis chain" sections of the solution. If the symptom file, taken together, conveys substantially the same information as the diagnosis — even using different words — it is a **semantic duplicate** of the solution and must be rewritten.

**Test:** Could an agent read ONLY the symptom file and produce a correct fix without running the code, reading the source, or doing any investigation? If yes → the symptom is diagnosis-equivalent and leaks at the document level.

### Step 4: Triage — classify each violation into tiers

For every violation found in Steps 2–3, classify it:

| If the information... | Tier | Action |
|---|---|---|
| Is externally observable without tools (crash msg, wrong output, missing data) | Tier 1 | Keep in `symptom.md` (reword if phrasing leaks) |
| Could be obtained with runtime tools (stack trace, logs, goroutine dump, metrics) AND does not reveal the fix location | Tier 2 | Extract to `context/` |
| Requires source code knowledge OR reveals fix location/strategy | Tier 3 | Redact entirely |

**The critical boundary is between Tier 2 and Tier 3.** Information that a developer could obtain from runtime tools (e.g., a stack trace) might still reveal the fix if it names the exact buggy function. Apply the debug-context anti-patterns below to decide.

### Step 5: Extract debug-context files

For violations classified as Tier 2, extract them into `cases/<case-name>/context/`.

#### Debug-context file types

Create separate markdown files by debug-context category. Only create files for categories that have content.

| File | Contains | Example content |
|---|---|---|
| `stack-trace.md` | Crash stack traces, goroutine dumps, panic output — sanitized (see below) | Go panic output with goroutine stacks; C++ ASAN/crash backtraces |
| `logs.md` | Relevant log output captured during reproduction | Server log lines showing the failure sequence; missing "start" messages after "stop" messages |
| `metrics.md` | Resource usage, timing data, counters at time of failure | Memory growth pattern; CPU spike timing; connection count anomalies |
| `config-state.md` | Configuration, cluster state, runtime flags at time of failure | Cluster membership; node roles; replication topology; runtime flags |
| `runtime-behavior.md` | Observable runtime behavior that requires tools to capture | Thread/goroutine states during hang; lock contention patterns visible in profiler; network packet timing |
| `test-output.md` | Test runner output showing the failure | Test assertion messages; diff output; expected vs actual |
| `error-output.md` | Full error messages, stderr output, exit codes | Complete error text beyond what fits in symptom's summary |

#### Debug-context file format

Each debug-context file must have this structure:

```markdown
# <Context Type>: <case-name>

## How this was obtained

<Brief description of the tool/method used to capture this debug context.
Must be a standard runtime tool — not source code reading.>

## Evidence

<The actual content — log lines, stack traces, metrics, etc.>

## What this tells a developer

<1-2 sentences describing what direction this debug context suggests,
WITHOUT naming the fix or the buggy code location.>
```

#### Debug-context sanitization rules

Before writing any debug-context file, sanitize it:

1. **Stack traces**: Keep the full trace shape (call depth, goroutine count, thread IDs) but redact frames that name functions from the solution's "Fix locus" → "Files" list if those frame names would uniquely identify the buggy function. Keep frames that are part of the runtime, standard library, or public API.
   - **Keep:** `runtime.gopanic`, `net/http.(*Server).Serve`, `main.main`
   - **Redact if fix-revealing:** The specific internal function that IS the bug (e.g., `processTxn` if that's the fix target). Replace with `<redacted:internal>` to preserve trace shape.
   - **Judgment call:** If the stack trace passes through the buggy function but the function name alone isn't enough to identify the fix (it's a large function, or the bug is in the caller's argument), keep it.

2. **Log lines**: Keep timestamps, log levels, and descriptive messages. Redact log messages that are only emitted from the buggy code path if they would pinpoint the exact location. Keep log messages that appear in normal operation too.

3. **Metrics**: Keep values and trends. Don't annotate which internal component is responsible for the anomaly unless that component name is user-facing.

### Step 5b: Recommend missing debug context (for clean cases)

If a case has zero violations but no `context/` directory, check whether natural Tier 2 debug context is missing based on the oracle type (from `case.yaml` or `verification.md`):

| Oracle type | Expected Tier 2 debug context | Tool to obtain it |
|---|---|---|
| CRASH | Stack trace, core dump backtrace | Captured from stderr/coredump on crash |
| HANG | Goroutine dump (Go), thread dump (Java), `gdb bt` (C++) | `kill -SIGQUIT`, `jstack`, `gdb -p` |
| OUTPUT | Diff of expected vs actual output | `diff` on test output |
| METRIC | Time-series snapshot, counter values at failure time | Monitoring endpoint, `/debug/vars`, `top`, `vmstat` |
| RACE | Race detector output | `-race` flag (Go), TSAN (C++) |
| LOG | Full log window around the failure (not just the failing line) | Server log file |

If natural debug context is missing, add a recommendation to the report:

```
RECOMMEND: <case-name> — no context/ directory. Consider adding:
  - context/stack-trace.md (CRASH case — capture goroutine dump from stderr)
```

This is advisory only — do not auto-create debug-context files from recommendation. The debug context must come from actually running the reproduction.

### Step 6: Rewrite symptom.md

After extracting Tier 2 content to context/ and redacting Tier 3 content:

1. Rewrite `symptom.md` to contain ONLY Tier 1 information
2. Apply the Fresh Developer Test to every sentence
3. Add a brief pointer at the end of symptom.md if debug-context files were created:
   ```markdown
   ## Additional debug context
   
   Runtime diagnostic artifacts are available in the `context/` directory.
   ```
4. Show before/after diff
5. Apply the edit

Rewriting guidelines:
- Replace internal data structure names with observable consequences ("missing data", "stale reads", "incorrect results")
- Replace protocol phase names with user-visible events ("after restart", "when the node rejoins", "during failover")
- Replace regression references with version ranges ("only affects v3.9.3+", "behavior changed in v2.2")
- Remove sentences that are purely diagnostic with no observable counterpart
- Keep: version numbers, reproduction steps, user-facing error messages, CLI commands, observable behavior (crash, hang, wrong output, missing data)

### Step 7: Report

For each file scanned, output a table:

```
## <case-name>

| Status | Type | Tier | Line | Violation | Action |
|--------|------|------|------|-----------|--------|
| LEAK   | lexical | 3:redact | 3 | Function name `processTxn` | Redacted |
| LEAK   | semantic:mechanism | 3:redact | 11 | "changed processTxn to a variant that does not populate committedLog" | Redacted |
| LEAK   | semantic:regression | 3:redact | 12 | "regression introduced by ZOOKEEPER-4394" | Redacted |
| LEAK   | semantic:narrowing | 2:context | 7 | "during the SYNCHRONIZATION phase" | → context/runtime-behavior.md |
| MOVE   | runtime-obtainable | 2:context | 9 | Stack trace showing crash path | → context/stack-trace.md |
| CLEAN  | — | 1:keep | — | — | — |
```

Debug-context extraction summary:
```
  Debug-context files created:
    - cases/<case-name>/context/stack-trace.md (from lines 8-12)
    - cases/<case-name>/context/logs.md (from lines 15-20)
```

### Step 8: Verify

Re-run ALL scans (lexical + semantic) on:
1. The edited `symptom.md` — must have zero violations
2. Each debug-context file — must have zero Tier 3 violations

Verification checklist:
- [ ] `symptom.md` passes the Fresh Developer Test (every sentence)
- [ ] `symptom.md` passes all 5 litmus tests
- [ ] Each debug-context file describes HOW it was obtained (runtime tool, not source reading)
- [ ] No debug-context file names the fix location or fix strategy
- [ ] No debug-context file is diagnostic-equivalent to the solution
- [ ] Stack traces are sanitized per the rules above

### Output format

```
=== Sanitize Report ===
Scanned: N cases
Clean: M cases
Violations found and fixed: K cases
  Tier 2 extractions (→ context/): P items
  Tier 3 redactions: Q items
  Breakdown:
    Lexical violations: X
    Semantic violations: Y
      - mechanism: A
      - regression: B
      - narrowing: C
      - fix-hint: D
      - diag-equiv: E
  Per-case:
    - <case-name>: N violations (types...), debug-context files created: [list]
    - <case-name>: N violations (types...)

Remaining violations: 0
```

## Anti-patterns

### Symptom anti-patterns (Tier 1)

- **Mechanism-as-symptom**: Describing the internal causal chain as if it were the observed behavior. E.g., "the in-memory log has a gap" — no user can observe an in-memory data structure; they observe missing data.
- **Regression breadcrumbs**: Naming the prior change, issue, or commit that introduced the bug. This gives the agent a direct `git log --grep` path to the fix.
- **Protocol-internal jargon**: Using terms like "DIFF sync", "SYNCHRONIZATION phase", "pre_vote state", "fencing message" when these are implementation details not visible in user-facing output. Exception: terms that appear in official documentation, CLI help, or user-visible log messages.
- **Inverted fix descriptions**: Describing what the code *fails to do* is equivalent to describing what the fix *should do*. E.g., "does not populate X" → fix is "populate X".
- **Over-specific scope**: "only happens when function A calls variant B instead of variant C" — this IS the diagnosis.
- **Diagnosis laundering**: Rewording the root cause from the solution using synonyms. If the solution says "processTxn(TxnHeader, Record) doesn't call addCommittedProposal()" and the symptom says "the transaction processing variant doesn't maintain the committed log", it's the same information.

### Debug-context anti-patterns (Tier 2)

These patterns mean the information should be Tier 3 (redacted), NOT Tier 2 (debug context):

- **Annotated stack traces**: A stack trace is OK; a stack trace with comments like "← this is where the bug is" or "this function should call X instead" is Tier 3.
- **Curated log snippets**: Showing ONLY the log lines from the buggy code path (as if you already know where the bug is) is Tier 3. Show the full log window around the failure instead.
- **Diff-ready descriptions**: "The log shows that function A is called but function B is not" — this is a diagnosis wearing debug-context clothing. Tier 3.
- **Single-function stack traces**: If the stack trace has been trimmed to show only the buggy function and its immediate callers, that's curation that reveals the fix location. Keep the full trace or redact.
- **Reverse-engineered internals**: "From the goroutine dump, we can see that the lock in syncWithLeader is held while..." — the developer obtained this from a goroutine dump (Tier 2 tool), but the interpretation names fix-locus internals (Tier 3 knowledge). Extract the raw goroutine dump; redact the interpretation.

### The key distinction

**Debug context shows WHAT is happening at runtime. Diagnosis explains WHY.**

- Debug context: "goroutine 47 is blocked on channel receive for >60s" → Tier 2
- Diagnosis: "the channel blocks because addCommittedProposal is never called" → Tier 3
- Debug context: "the server log shows 'stop replication' but no subsequent 'start replication'" → Tier 2
- Diagnosis: "the replication routine is not restarted because the same server regains leadership" → Tier 3

## Litmus tests

Apply ALL of these. If any answers "yes" for symptom.md, it still leaks:

1. **Grep test**: Could an agent grep the codebase using terms from this symptom file and land on the fix location?
2. **Diagnosis test**: Could an agent read ONLY this symptom file and produce a correct fix without reading any source code?
3. **Fresh developer test**: Would a developer need to have read the source code to write this sentence?
4. **Narrowing test**: Does this symptom file reduce the search space from "entire codebase" to "a specific function/file/module"?
5. **Diff test**: Could an agent use information in this file to identify the exact commit that introduced the regression?

Apply these for debug-context files — if any answers "yes", the context file leaks and needs sanitization:

6. **Fix-from-context test**: Could an agent read ONLY this debug-context file and know exactly which function/line to change?
7. **Curation test**: Does the debug context look like it was selected by someone who already knows the answer? (Only showing the relevant 3 lines from a 500-line log is curation.)
8. **Interpretation test**: Does the debug context contain analysis/interpretation that requires source code knowledge, rather than raw runtime output?
