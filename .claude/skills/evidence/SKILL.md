# /evidence — Debugging Evidence Generator

Generate realistic debugging evidence for bug cases by running actual debugging tools (GDB, race detectors, log capture, ASAN, jstack, etc.) against the buggy system. Evidence files contain raw tool output only — no analysis, no interpretation, no explanation of what the output means.

Use this skill when creating or enriching bug cases with Tier 2 evidence, when a case has no `evidence/` directory, or when the user asks to generate debugging clues for a case. Also use when the user mentions "evidence", "debugging clues", "diagnostic artifacts", or "add evidence to cases".

## Usage

```
/evidence <case-name>       # generate evidence for one case
/evidence all               # generate evidence for all cases missing it
/evidence <case-name> --refresh   # regenerate even if evidence/ exists
```

---

## Core Principle: Raw Tool Output, Nothing Else

Evidence is **raw output from debugging tools**. Period.

An evidence file contains:
1. One sentence saying how the output was obtained (which tool, which command)
2. The raw tool output, verbatim

An evidence file does NOT contain:
- Analysis of what the output means
- Explanation of what it "tells a developer"
- Decoded internal constants or annotated output
- Reconstructed timelines or protocol breakdowns
- Source code snippets or grep results
- Any section titled "Analysis", "Interpretation", "What this tells a developer", or similar
- Any modification to `symptom.md` — evidence and symptoms are completely separate; evidence is injected as system prompt at benchmark time, never referenced from symptom files

```
GOOD evidence file:              BAD evidence file:
─────────────────                ────────────────
One-sentence provenance          Multi-paragraph explanation
Raw GDB backtrace                "The deadlock involves three threads..."
Raw race detector output         "This tells a developer that..."
Raw test failure output          Decoded flags: 0x06 (FLAG_DO_FENCING|...)
Raw server logs                  Reconstructed timeline with analysis
```

### What developers actually get

This benchmark tests how agents debug. The agent works **inside a Docker container** at `/workspace/worktrees/<case>/` with only the built source code. It has no reproduce scripts, no bench.sh, no host access. Evidence must reflect what a developer would obtain by running standard tools from inside that workspace:

- Test output from running an existing test (`go test`, `mvn test`, `gradle test`, `rebar3 ct`)
- Race detector output from `go test -race`
- A goroutine dump from sending SIGQUIT to a hung Go process
- GDB backtrace from attaching to a hung or crashed C++ process
- jstack output from a hung Java process
- ASAN/TSAN/Valgrind output from running under sanitizers
- Server logs captured during the failure
- Crash stderr from starting a process with bad input

The provenance line in evidence files must show the command **as a developer would run it inside the workspace** — not `bench.sh` anything, not host paths.

### No Fabrication

Evidence must come from **actually running tools against the buggy system**. If you cannot reproduce the bug in the current environment, write a placeholder — never fabricate output. A placeholder that says "run GDB and capture the backtrace" is honest. A fabricated backtrace is fiction.

---

## Evidence File Format

Every evidence file follows this exact structure:

```markdown
# <Evidence Type>

Obtained by running `<exact command>` against the buggy build.

## Output

<Raw tool output, verbatim. No annotations, no inline comments,
no decoded constants, no added context. Just the output.>
```

That's it. No other sections. No "Analysis". No "What this tells a developer". No "Interpretation". No "Critical Window". Nothing.

If the raw output is very long, trim it to the relevant window (keep 10-30 lines of context around the interesting part so it doesn't look cherry-picked). You may truncate with `[... N lines omitted ...]` but never add lines.

---

## Procedure

### Step 1: Read case materials

For the target case, read these files in parallel:

```
cases/<case-name>/symptom.md
cases/<case-name>/reproduce.md
cases/<case-name>/verification.md
cases/<case-name>/case.yaml
cases-solution/<case-name>/solution.md
```

From these, determine: what kind of bug is this (crash, hang, data loss, race, etc.), what language/project, and what tools a developer would naturally reach for.

If `cases/<case-name>/evidence/` already exists and `--refresh` was not passed, report what's there and skip unless files look incomplete.

### Step 2: Set up the case

```bash
./bench.sh setup <case-name>
```

If setup fails or Docker is unavailable, use placeholders (see below).

### Step 3: Select evidence types

Pick 1-3 evidence types that are natural for this bug category:

| Bug Category | Natural Evidence | Developer Tool |
|---|---|---|
| **Crash** (segfault, SIGABRT) | Stack trace, ASAN output | GDB, ASAN, crash stderr |
| **Hang / Deadlock** | Thread/goroutine dump | GDB `thread apply all bt`, SIGQUIT, jstack |
| **Data loss / Corruption** | Test output, server logs | Test runner, log files |
| **Race condition** | Race detector output | `go test -race`, TSAN |
| **Memory error** | Sanitizer output | Valgrind, ASAN |
| **Logic error** | Test output diff | Test runner |
| **Resource leak** | Metrics over time | pprof, `/debug/vars`, `lsof` |

### Step 4: Run tools and capture output

You (the skill operator) use `bench.sh` to set up and enter the container. But the **evidence provenance line** must show only the command as run inside the workspace — because that's what the agent will see.

```bash
# YOU do this (not recorded in evidence):
./bench.sh setup <case-name>
./bench.sh shell <case-name>

# INSIDE the container at /workspace/worktrees/<case>/, run the developer command:
#   Go test:        go test -run TestFoo -count=1 -v ./pkg/...
#   Go race:        go test -race -run TestFoo -count=5 ./pkg/...
#   Go goroutines:  kill -SIGQUIT <pid>
#   GDB:            gdb --batch -ex run -ex bt -ex "thread apply all bt" --args ./binary
#   Maven test:     mvn -pl module test -Dtest="TestClass#method"
#   Gradle test:    ./gradlew :module:test --tests "pkg.TestClass.method"
#   ASAN:           ASAN_OPTIONS=detect_leaks=1 ./binary
#   jstack:         jstack <pid>
#   Erlang:         rebar3 ct --suite=test_SUITE
```

Capture the output inside the container:

```bash
<command> 2>&1 | tee /tmp/evidence-raw-<case-name>.txt
```

The evidence file provenance line should read like:
- `Obtained by running go test -race -run TestEmbedEtcd -count=5 ./tests/integration/embed/`
- `Obtained by running gdb --batch -ex run -ex bt --args ./build/dragonfly --port 6379`
- `Obtained by running mvn -pl bookkeeper-server test -Dtest="FooTest#barMethod"`

NOT:
- `./bench.sh reproduce ...`
- `cd /home/user/projs/ddbench/... && ./bench.sh ...`
- Any host path or bench.sh command

### Step 5: Write evidence files

Create `cases/<case-name>/evidence/` and write files using ONLY content from the captured output.

The file must follow the format in the "Evidence File Format" section above. Every line in the `## Output` section must come from the captured raw output. You may trim for length but never add content.

**Verification gate:** After writing, re-read the evidence file. Every non-trivial line under `## Output` must appear in `/tmp/evidence-raw-*.txt`. If any line doesn't, the file is fabricated — delete it.

### Step 6: Anti-leak checks

Before finalizing, verify evidence does not leak the fix:

1. **Native output test**: Every line under `## Output` must be something the tool actually produced. No annotations, no decoded constants, no source-derived commentary.

2. **Fix-from-evidence test**: Could someone read ONLY this file and know exactly which function/line to fix? If yes, it's too specific.

3. **Curation test**: Does it look cherry-picked by someone who knows the answer? Include realistic context (multiple threads in a dump, surrounding log lines), not just the smoking gun.

4. **Term check**: Evidence must NOT contain function names that are the direct fix target, variable names from the fix diff, or internal constant names decoded from source.

5. **Grep test**: Could someone grep the codebase for terms in this evidence and land directly on the buggy function? If so, redact unique identifiers.

### Step 7: Report

```
=== Evidence: <case-name> ===
Files created:
  - evidence/<filename>.md — <tool used>
Leak checks: PASSED
```

---

## Placeholders (when reproduction unavailable)

```markdown
# <Evidence Type>

## Status: NOT YET CAPTURED — requires reproduction

**Tool:** <exact command to run>
**Expected output type:** <e.g., "ASAN heap-buffer-overflow report", "goroutine dump">
```

---

## Batch Mode (`/evidence all`)

1. List all case directories
2. Skip cases that already have evidence (unless `--refresh`)
3. Process remaining cases sequentially
4. Print summary:

```
=== Batch Evidence Report ===
Total: 62 | Already had evidence: N | Generated: M | Errors: K
```

---

## Evidence File Naming

| Evidence Type | Filename |
|---|---|
| GDB backtrace | `gdb-backtrace.md` |
| Goroutine dump | `goroutine-dump.md` |
| Java thread dump | `jstack-dump.md` |
| Server logs | `logs.md` |
| Race detector | `race-detector.md` |
| ASAN/TSAN | `sanitizer-output.md` |
| Test output | `test-output.md` |
| Test failure | `test-failure.md` |
| Crash stderr | `crash-output.md` |
| Hang/timeout | `hang-timeout.md` |
| Metrics | `metrics.md` |
| CT failure (Erlang) | `ct-failure.md` |

---

## Common Mistakes to Avoid

1. **Writing analysis**: Your job is to paste raw output. Not to explain it. Not one paragraph. Not one sentence of interpretation beyond the provenance line. If you catch yourself writing "this shows that..." or "the deadlock involves..." — stop and delete it.

2. **Using `bench.sh` or host commands in evidence**: The agent works inside a container with only workspace code. Evidence provenance must show commands a developer runs inside the workspace (`go test`, `gdb`, `mvn test`, etc.) — never `bench.sh`, never host paths.

3. **Source-code analysis as evidence**: `grep` over source, decoded flag constants, protocol breakdowns, code snippets — none of these are tool output. They are source analysis (Tier 3). Delete them.

4. **Prose summaries instead of output**: "A GDB backtrace reveals the deadlock: one thread holds X while another waits on Y" is analysis. The actual GDB backtrace output is evidence.

5. **Numbered multi-file sequences**: Don't create `01_foo.md`, `02_bar.md`, `03_analysis.md`. Create 1-3 files named by evidence type. If file 03 is "protocol flag inspection" or "recovery phase timeline", it's analysis — don't create it.

6. **Modifying symptom.md**: Never touch symptom.md. Evidence and symptoms are completely separate artifacts. Evidence is injected as system prompt at benchmark time — it is never referenced from symptom files. Do not add "Additional evidence" pointers or any other cross-references.

7. **Language mismatch**: Use the right tool for the language:
   - **C++**: GDB, ASAN/TSAN, Valgrind
   - **Go**: goroutine dumps (SIGQUIT), `-race`, pprof, delve
   - **Java/Scala**: jstack, test runner output
   - **Erlang**: `rebar3 ct`, crash dumps, `erlang:process_info/2`
   - **Rust**: GDB/LLDB, ASAN/TSAN
