# /evidence — Debugging Evidence Generator

Generate realistic debugging evidence for bug cases. Reads the symptom file and solution to understand the bug, then produces evidence files representing what a developer would realistically discover using standard debugging tools (GDB, logging, tracing, valgrind, race detectors, goroutine dumps, etc.) — without leaking the fix.

Use this skill when creating or enriching bug cases with Tier 2 evidence, when a case has no `evidence/` directory, or when the user asks to generate debugging clues for a case. Also use when the user mentions "evidence", "debugging clues", "diagnostic artifacts", or "add evidence to cases".

## Usage

```
/evidence <case-name>       # generate evidence for one case
/evidence all               # generate evidence for all cases missing it
/evidence <case-name> --refresh   # regenerate even if evidence/ exists
```

---

## Core Principle: Evidence Shows WHAT, Never WHY

Evidence is what a developer **obtains by running tools** against the buggy system. It narrows the investigation without pinpointing the fix.

```
 Evidence (Tier 2)                    NOT Evidence (Tier 3)
 ─────────────────                    ─────────────────────
 "Thread 3 blocked on rwlock"         "The lock in PrepareRestoreDB causes..."
 "goroutine 47: chan receive, 60s"    "addCommittedProposal is never called"
 "ASAN: heap-use-after-free"          "The RDB encoding frees the buffer too early"
 "Log: 'stop replication' with no     "The replication routine is not restarted
  subsequent 'start replication'"      because the same server regains leadership"
 "Phase 1 request flags=0x06,         "Phase 2 is missing FLAG_DO_FENCING
  Phase 2 request flags=0x02"          (0x04) in the flags computation"
```

The developer seeing evidence still needs to read source code to understand the root cause.

### No Fabrication — Evidence Must Be Real

Evidence must come from **actually running tools against the buggy system**, not from reading the solution and generating plausible-looking output. Fabricated evidence — no matter how realistic it looks — is not evidence. It is fiction dressed as data.

To produce real evidence:
1. **Set up the case**: `./bench.sh setup <case-name>` (or `./setup.sh` on host)
2. **Run the reproduction** under the appropriate tool (ASAN, GDB, race detector, DEBUG logs, etc.)
3. **Capture the raw output** exactly as the tool produces it
4. **Sanitize** per the leak checks below (redact fix-revealing frames/lines if needed)

If the case **cannot be reproduced** in the current environment (no Docker, missing dependencies), do NOT fabricate output. Instead, write a placeholder evidence file that documents:
- Which tool should be run and how
- What the expected evidence type would be
- Mark it as `## Status: NOT YET CAPTURED — requires reproduction`

A placeholder that says "run GDB and capture the backtrace" is honest. A fabricated backtrace that looks real but came from reading the solution is dishonest and useless — it adds no information beyond what the solution already contains.

### The Native Output Rule

Every line in the "Evidence" section must be **real output from a real tool run**. No annotations, no decoded internal constant names, no source-code-derived commentary mixed into raw output.

If you need to interpret raw output (e.g., explain what hex values might mean, note patterns in log timing), that interpretation goes in the "What this tells a developer" section, framed as inference from the observable data.

Annotations that decode internal constants (e.g., `flags=0x06 (FLAG_DO_FENCING|FLAG_HIGH_PRIORITY)`) require reading source code to produce. The raw hex value is tool output; the decoded flag names are source-code knowledge. Mixing them makes fabricated data look like runtime evidence while actually leaking the diagnosis.

---

## Procedure

### Step 1: Read case materials and set up reproduction

For the target case, read these files in parallel:

```
cases/<case-name>/symptom.md          # what the user observes
cases/<case-name>/reproduce.md        # how to trigger
cases/<case-name>/verification.md     # pass/fail criteria
cases/<case-name>/case.yaml           # project, language, build info
cases-solution/<case-name>/solution.md  # root cause + fix (PRIVATE — never leak)
```

If `cases/<case-name>/evidence/` already exists and `--refresh` was not passed, report what's there and skip unless files look incomplete.

Then set up the case for reproduction:

```bash
./bench.sh setup <case-name>
```

If setup fails or Docker is unavailable, note this in the report. Do NOT proceed to fabricate evidence — use placeholders instead (see "No Fabrication" above).

### Step 2: Classify the bug and select evidence types

From the solution's root cause and the symptom, determine the bug category and which evidence types are natural fits.

| Bug Category | Natural Evidence Types | Tools |
|---|---|---|
| **Crash** (segfault, SIGABRT, panic) | Stack trace, ASAN/TSAN output, core dump backtrace | GDB, ASAN, crash stderr |
| **Hang / Deadlock** | Thread dump, goroutine dump, GDB backtrace of all threads, lock contention | GDB `thread apply all bt`, `kill -SIGQUIT` (Go), `jstack` (Java) |
| **Data loss / Corruption** | Log sequences, protocol-level traces, before/after data snapshots, test assertion output | Server logs, `tcpdump`, diff, test runner |
| **Stale read / Linearizability** | Log sequences showing write-then-read inconsistency, timing observations, test output | Logs, test assertions, timing instrumentation |
| **Race condition** | Race detector output, TSAN report, intermittent test failures with iteration counts | `-race` (Go), TSAN (C++), repeated test runs |
| **Memory error** (use-after-free, leak) | Valgrind/ASAN output, heap profile snapshots | Valgrind, ASAN, heap profiler |
| **Logic error** (wrong output, wrong behavior) | Test output diffs, log sequences, metric snapshots | Test runner, diff, monitoring |
| **Resource leak** | Metric trends over time (goroutine count, fd count, memory), logs showing accumulation | `/debug/vars`, `lsof`, `top`, pprof |
| **Election / Liveness** | Log sequences showing repeated state transitions, timing between events | Server logs, cluster monitoring |

Select 1-3 evidence types that are most natural for this bug. Prefer fewer, higher-quality evidence files over many thin ones.

### Step 3: Capture — Run tools and save raw output

This step has a strict ordering: **run first, write later**. You must execute a real command and capture its output before writing any evidence file. This prevents fabrication structurally.

#### 3a. Run the tool and capture output to a file

For each evidence type selected in Step 2, run the tool and tee the output:

```bash
# The reproduce script is the most common evidence source — it runs
# the test/trigger and prints pass/fail output:
./bench.sh reproduce <case-name> 2>&1 | tee /tmp/evidence-raw-<case-name>.txt

# For other evidence types, run inside the container:
# Crash (C++): ASAN
#   docker exec <container> bash -c 'bash /bench/reproduce.sh 2>&1' | tee /tmp/evidence-asan.txt

# Crash (C++): GDB backtrace
#   docker exec <container> bash -c 'gdb --batch -ex run -ex bt -ex "thread apply all bt" --args ./binary <flags> 2>&1' | tee /tmp/evidence-gdb.txt

# Hang/Deadlock (C++): GDB on hung process
#   docker exec <container> bash -c 'gdb -p <pid> -batch -ex "thread apply all bt" 2>&1' | tee /tmp/evidence-threads.txt

# Hang (Go): goroutine dump
#   docker exec <container> bash -c 'kill -SIGQUIT <pid>' 2>&1 | tee /tmp/evidence-goroutines.txt

# Race (Go): race detector
#   docker exec <container> bash -c 'go test -race -count=10 ./path/to/pkg/ 2>&1' | tee /tmp/evidence-race.txt

# Hang (Java): jstack
#   docker exec <container> bash -c 'jstack <pid> 2>&1' | tee /tmp/evidence-jstack.txt

# Logs: capture server logs during reproduction
#   docker exec <container> bash -c 'cat /path/to/server.log' | tee /tmp/evidence-logs.txt
```

The key: the captured file (`/tmp/evidence-raw-*.txt`) is the source of truth. Every line in the Evidence section of the final file MUST come from this captured output.

#### 3b. Read the captured output

Read the captured file. Identify the relevant portion — usually the test output section (after build output), the crash/error section, or the relevant log window.

#### 3c. Write the evidence file from captured content

Create `cases/<case-name>/evidence/` and write evidence files using ONLY content from the captured output. Each file must follow this format:

```markdown
# <Evidence Type>: <case-name>

## How this was obtained

<The exact command that was run. Copy it from step 3a.>

## Evidence

<Paste the relevant portion of the captured output verbatim.
Do NOT rephrase, annotate, or embellish. The content must be
a substring of the captured raw output file, possibly trimmed
for length but never modified.>

## What this tells a developer

<1-3 sentences describing the investigative direction this evidence suggests.
Frame as questions or observations, NOT answers.>
```

#### 3d. Fabrication verification gate

After writing each evidence file, verify it is not fabricated:

1. **Read back the evidence file** you just wrote.
2. **For each non-trivial line in the Evidence section**, confirm it appears in the captured raw output file (`/tmp/evidence-raw-*.txt`). Trivial lines are markdown formatting (```, blank lines, section headers).
3. If ANY content line in the Evidence section does not appear in the captured output, the evidence is fabricated. **Delete the file** and either:
   - Re-run the tool with different flags to capture the missing output, OR
   - Convert to a placeholder file (see "What if reproduction is not available?" below)

This gate is non-negotiable. If you cannot point to the captured output file that contains the evidence, the evidence file must not exist.

**Why this matters:** Fabricated evidence looks real but contains no information that wasn't already in the solution. It wastes the developer's time by making them think they're looking at tool output when they're actually looking at a restatement of the diagnosis. Real evidence contains details the solution might not mention — exact error messages, timing, thread IDs, memory addresses — that can help a developer build their own mental model.

### Step 4: Sanitize — apply anti-leak checks

Before finalizing each evidence file, verify it does not leak the fix. Apply EVERY check below — a single failure means the evidence needs revision.

**Leak check 1 — Native output test (CRITICAL):**
Every line in the "Evidence" section must be something the tool would actually produce on its own, without the developer adding annotations from source-code knowledge. This is the most common leak vector.

Examples of violations:
- Log output that decodes internal constants into symbolic names (e.g., `flags=0x06 (FLAG_DO_FENCING|FLAG_HIGH_PRIORITY)`) when the real tool only outputs raw values (e.g., `flags=0x06`). The parenthetical decoding requires reading the source to know what the bits mean.
- Stack traces with inline comments like `← this is where the lock is acquired`
- Trace output annotated with `NOTE: buf.delete is NOT called` — the trace tool doesn't know what "should" be called
- "Instrumented" trace logs that narrate internal state transitions in a way no real logging framework would produce

**The test:** For each line in the Evidence section, ask: "Would this exact text appear in the terminal if I ran this tool right now, with no source-code modifications beyond standard debug flags?" If not, it's a leak.

For annotations that help readability (e.g., decoding hex flags), move them to the "What this tells a developer" section and frame as inference: "The hex value 0x06 in Phase 1 differs from 0x02 in Phase 2, suggesting a missing flag bit."

**Leak check 2 — Fix-from-evidence test:**
Could an agent read ONLY this evidence file and know exactly which function/line to change? If yes, the evidence is too specific. Generalize it.

**Leak check 3 — Curation test:**
Does the evidence look like it was cherry-picked by someone who already knows the answer? For logs: show a realistic window (10-30 lines around the interesting part), not just the 2 smoking-gun lines. For stack traces: show multiple threads/goroutines, not just the one with the bug.

**Leak check 4 — Interpretation test:**
Does the "What this tells a developer" section require source code knowledge? It should suggest directions ("investigate lock ordering", "check if deletes flush the same way as writes") not conclusions ("the bug is in PrepareRestoreDB"). It may reference raw values from the evidence (hex codes, error strings) and reason about them, but must not decode them using source-code-only knowledge.

**Leak check 5 — Term check:**
Cross-reference against the solution's fix locus. Evidence must NOT contain:
- Function names that are the direct fix target (functions in the call path are OK if they're public/well-known)
- Variable or field names from the fix diff
- The component name from "Fix locus" verbatim (paraphrase if needed)
- Internal constant names (FLAG_DO_FENCING, BATCH_LIMIT, etc.) unless they appear verbatim in the tool's native output — check this by verifying the project's actual log format

**Leak check 6 — Grep test:**
Could someone grep the codebase for terms in this evidence and land directly on the buggy function? If unique internal identifiers appear, redact or generalize them.

**Leak check 7 — Annotation audit:**
Scan the Evidence section for parenthetical annotations, inline comments, or decoded values. Each one must pass the native output test (check 1). If in doubt, remove the annotation — raw output is always safer than annotated output.

### Step 5: Update symptom.md pointer

If evidence files were created and `symptom.md` doesn't already reference them, append:

```markdown

## Additional evidence

Runtime diagnostic artifacts are available in the `evidence/` directory.
```

### Step 6: Final evidence folder audit

Before reporting, sweep the entire `cases/<case-name>/evidence/` directory to ensure it is clean. For each `.md` file in the folder:

1. **Check for a raw capture file.** Every evidence file must trace back to a `/tmp/evidence-*` capture file created in Step 3a. If no capture file exists for this evidence file, it was fabricated.

2. **Check the Evidence section content.** Read the file, extract the content between `## Evidence` and the next `##` heading. Verify at least one non-trivial line from this section exists in the corresponding capture file.

3. **Classify each file:**

| Status | Meaning | Action |
|---|---|---|
| `VERIFIED` | Evidence section content matches captured raw output | Keep |
| `PLACEHOLDER` | File contains `## Status: NOT YET CAPTURED` | Keep (honest) |
| `FABRICATED` | No capture file, or evidence content not found in any capture | **Delete** |
| `STALE` | From a prior run, not created in this session | **Delete** (unless `--keep-existing` flag) |

4. **For each `FABRICATED` file:** Delete it. Then decide:
   - If the tool CAN be re-run: go back to Step 3a, run the tool, capture output, and recreate the evidence file from real data.
   - If the tool CANNOT be re-run: replace with a placeholder file (see "What if reproduction is not available?" below).
   - Do NOT silently keep fabricated files.

5. **Final state guarantee:** After this step, every file in `evidence/` is either `VERIFIED` (backed by real capture) or `PLACEHOLDER` (honestly marked as not yet captured). Zero fabricated files remain.

```
Evidence folder audit: <case-name>
  test-output.md — VERIFIED (from /tmp/evidence-raw-etcd-17158.txt)
  logs.md — PLACEHOLDER (requires cluster reproduction)
  old-fabricated.md — FABRICATED → DELETED
  Final: 1 verified, 1 placeholder, 1 deleted
```

### Step 7: Report

```
=== Evidence Report: <case-name> ===
Bug category: <category>
Evidence files created:
  - evidence/<filename>.md — <brief description> (obtained via: <tool>)
  - evidence/<filename>.md — <brief description> (obtained via: <tool>)
Leak checks: PASSED
Fabrication audit: CLEAN (N verified, M placeholders, K deleted)
symptom.md: <updated | already had pointer | unchanged>
```

---

## Sanitization of Real Output

Real tool output (captured in Step 3a) may contain information that leaks the fix. When trimming captured output for the evidence file (Step 3c), apply these rules:

1. **Stack traces**: Keep the full trace from the captured output. But if it passes through the exact fix-target function in a way that uniquely identifies the bug, replace that single frame with `<internal>` to preserve trace shape. Use judgment: a function in 50 stack traces is not identifying; one that only appears in the crash path may be.

2. **Log output**: Include a window of 10-30 lines from the captured logs, not just the failure point. Include normal-operation lines for context.

3. **Test output**: Include the full test runner output (pass/fail, assertion messages, timing) as captured. Do not include the test source code itself.

4. **Build output**: Strip build/compilation output — it's noise. Only include the test/tool output portion.

5. **Never add content**: You may trim, truncate, or redact lines from captured output. You may NEVER add lines that weren't in the captured output. The evidence section is a subset of the raw capture, never a superset.

## What if reproduction is not available?

If `bench.sh setup` fails, Docker is unavailable, or the tool cannot be run, create placeholder evidence files:

```markdown
# <Evidence Type>: <case-name>

## Status: NOT YET CAPTURED — requires reproduction

## Tool and command

<Exact command to run when reproduction is available>

## Expected evidence type

<What kind of output this would produce — e.g., "ASAN heap-buffer-overflow report",
"goroutine dump showing blocked goroutines", "test assertion showing stale read">

## What to look for

<What patterns in the real output would be informative for debugging,
WITHOUT naming the fix or root cause>
```

Placeholders are honest. Fabricated tool output is not.

---

## Batch Mode (`/evidence all`)

When running on all cases:

1. List all case directories: `ls cases/`
2. For each case, check if `evidence/` exists and is non-empty
3. Skip cases that already have evidence (unless `--refresh`)
4. Process remaining cases sequentially
5. Print summary:

```
=== Batch Evidence Report ===
Total cases: 62
Already had evidence: 5
Generated evidence: 47
Skipped (no solution): 0
Errors: 0

Per-case:
  [NEW] kafka-15170-endless-rebalance-loop — 2 files (logs.md, metrics.md)
  [NEW] etcd-17158-delete-linearizability — 1 file (test-output.md)
  [SKIP] kvrocks-2512-slaveof-deadlock — already has evidence/
  ...
```

---

## Evidence File Naming

Use descriptive filenames matching the evidence type:

| Evidence Type | Filename |
|---|---|
| GDB / thread backtrace | `gdb-backtrace.md` |
| Goroutine dump | `goroutine-dump.md` |
| Java thread dump | `jstack-dump.md` |
| Server/application logs | `logs.md` |
| Race detector output | `race-detector.md` |
| ASAN / TSAN output | `sanitizer-output.md` |
| Valgrind output | `valgrind-output.md` |
| Test assertion output | `test-output.md` |
| Metrics / resource usage | `metrics.md` |
| Network / protocol trace | `network-trace.md` |
| Core dump analysis | `core-dump.md` |
| Regression notes | `regression.md` |
| Config / cluster state | `cluster-state.md` |

If a case needs two files of the same type (rare), suffix with a descriptor: `logs-startup.md`, `logs-failover.md`.

---

## Common Pitfalls

1. **Annotated raw output (most common leak vector)**: The evidence section must be raw tool output only. Never add parenthetical decodings like `flags=0x06 (FLAG_DO_FENCING|FLAG_HIGH_PRIORITY)` — the tool outputs `flags=0x06`, the decoded names come from reading source. Never add inline comments like `← this blocks` or `NOTE: function X is not called`. If you need to explain what raw values mean, do it in the "What this tells a developer" section as inference from the observable data.

2. **Source analysis disguised as tooling**: `grep` over source code is not runtime evidence. Method override tables, interface implementation audits, and code path tracing are source-code analysis, not tool output. Evidence comes from running the system, not reading the code. If you find yourself writing "grep -n 'func.*MethodName' source_file.go" — stop, that's Tier 3.

3. **Over-specificity in "What this tells a developer"**: This section should open doors, not close them. "The lock ordering between X and Y deserves investigation" is better than "X acquires the lock before Y, which is wrong." It may reference raw values from the evidence (e.g., "the hex flags differ between Phase 1 and Phase 2") but must not decode them using internal constant names.

4. **Unrealistic tool output**: If you're generating a GDB backtrace for a Go program, that's wrong — Go uses goroutine dumps via `SIGQUIT` or `runtime/pprof`. Match the tool to the language.

5. **Too few goroutines/threads**: A real dump shows ALL goroutines/threads, not just the interesting one. Include 3-8 with a mix of blocked and running states.

6. **Perfect log windows**: Real developers capture more logs than needed. Include some normal-operation noise lines, not just the exact failure sequence.

7. **Language mismatch**: Use the right tools for the right language:
   - **C++**: GDB, Valgrind, ASAN/TSAN, core dumps
   - **Go**: goroutine dumps (`SIGQUIT`), `-race` flag, pprof, delve
   - **Java/Scala**: jstack, JMX, heap dumps, JFR
   - **Erlang**: `observer`, `dbg`, crash dumps, `erlang:process_info/2`
   - **Rust**: GDB/LLDB, ASAN/TSAN, `tracing` crate output
