# /debug-context — Debug-Context Generator

Generate debug context for bug cases by acting as a developer investigating the symptom inside the Docker container. You read `symptom.md`, enter the container at the buggy commit, and use standard debugging tools and source code investigation to gather clues — exactly as a real developer would. Debug-context files contain raw tool output and/or structured code investigation notes.

Use this skill when creating or enriching bug cases with Tier 2 debug context, when a case has no `context/` directory, or when the user asks to generate debugging clues for a case. Also use when the user mentions "debug context", "debugging clues", "diagnostic artifacts", or "add debug context to cases".

## Usage

```
/debug-context <case-name>       # generate debug context for one case
/debug-context all               # generate debug context for all cases missing it
/debug-context <case-name> --refresh   # regenerate even if context/ exists
```

---

## Core Principle: You Are a Developer Debugging From the Symptom

You are not a test runner. You are a developer who has been told about a bug (via `symptom.md`) and is now investigating inside the container. You have the full built source at the buggy commit, standard debugging tools, and nothing else.

Your job is to gather debug context that helps narrow down the bug — crash backtraces, suspicious log output, race detector reports, test failures, unexpected server behavior, and code investigation notes. The debug context should be useful debugging clues, not a proof that the bug exists.

There are two kinds of debug context, and a case can have both:

### Runtime Context
Raw output from running tools (GDB, race detector, test runner, server + CLI, etc.). This is always preferred when available. Runtime context does NOT contain analysis or interpretation — just the raw output with a provenance line.

### Code-Investigation Context
A developer investigating a bug reads source code. Code-investigation context captures this process: what the developer searched for (motivated by the symptom), what they found (raw grep/sed output), and what hypothesis they formed. This is how a developer naturally narrows a problem — they don't jump to the root cause, they follow leads.

The critical constraint: code investigation must reflect **intermediate reasoning**, not the final diagnosis. Think of it as a developer's notes after 30 minutes of reading code — they've found something suspicious but haven't connected all the dots yet. The hypothesis should point **toward the problem area** without naming the exact fix or root cause.

```
GOOD debug context:                      BAD debug context:
───────────────────                      ───────────────────
GDB backtrace from a crash               "The fix is to add FLAG_DO_FENCING..."
Race detector output                     Output from an injected regression test
Server logs showing anomaly              Decoded constants from reading the fix
Code investigation with hypothesis       Code investigation that names the exact fix
"This function doesn't check X..."       "Change line 47 to add the missing call"
grep output showing a suspicious gap     Reconstructed timeline with full analysis
```

---

## CRITICAL: Agent-Accessible Debug Context Only

The agent works **inside a Docker container** at `/workspace/worktrees/<case>/` with only the built source code at the buggy commit. It has:
- The full project source and built binaries at the buggy commit
- Standard development tools (GDB, Go toolchain, Maven, cargo, rebar3, etc.)
- Network tools (redis-cli, etcdctl, nats CLI, curl, etc.)

Debug context must NOT depend on:
- `reproduce.sh`, `bench.sh`, or any case scripts (`bench.sh agent` never mounts the case dir, so these files are invisible to agents)
- Injected test files (regression tests cherry-picked from the fix commit)
- Files from the `inject_test/` directory
- The `cases/` or `cases-solution/` directories

**Every piece of debug context must be obtainable by the agent using only what exists at the buggy commit.** This means:

- **NEVER run `reproduce.sh`** as a debug-context source. It often injects test files that don't exist at the buggy commit. More fundamentally, **its output is the oracle**: its trigger, thresholds, observation window, and verdict. Context with oracle information tells the agent exactly how it will be graded. This holds even when reproduce.sh injects nothing.
- **NO oracle information in any form:** no `PASS:`/`FAIL:`/`Bug is present` lines, no oracle thresholds, windows, or data sizes, and no rewording of reproduce.sh's steps or messages. Use your own scenario parameters (e.g. the project's default ports, not the oracle's). The provenance line describes the *symptom condition* ("while the replica had stopped consuming"), not the oracle's trigger recipe.
- **NEVER use output from injected tests** — if `reproduce.sh` writes `FooTest.java` or `bug_test.go` into the source tree, that test doesn't exist for the agent
- **ALWAYS work from clean buggy commit state** — enter via `bench.sh shell` (which does NOT run reproduce.sh) or reset with `bench.sh reset`

### How to verify: the container test

Before writing any debug-context file, ask: "Could an agent inside the container at `/workspace/worktrees/<case>/` — with only the buggy commit source, no case scripts, no injected files — actually run this command and get this output?"

If the answer is no, the debug context is invalid.

---

## Debug-Context File Formats

### Runtime Context Format

```markdown
# <Context Type>

Obtained by running `<exact command>` against the buggy build.

## Output

<Raw tool output, verbatim. No annotations, no inline comments,
no decoded constants, no added context. Just the output.>
```

No other sections. No "Analysis". No "Interpretation". If the raw output is very long, trim to the relevant window (keep 10-30 lines of context). You may truncate with `[... N lines omitted ...]` but never add lines.

### Code Investigation Format

Code investigation mimics a developer reading source code to form a debugging hypothesis. It captures the search process, not the conclusion. Think of it as a developer's notebook after their first pass through the codebase — they've spotted something that doesn't look right, but they haven't proven it's the bug yet.

```markdown
# Code Investigation

## What was searched

<1-2 sentences: what the developer looked for, motivated by the symptom.
E.g., "Based on the symptom of watch events being lost after compaction,
searched for how the watcher sync loop handles compaction notifications.">

## What was found

<Raw grep/sed/cat output showing the relevant code. This must be actual
command output from inside the container — not hand-copied or paraphrased.
Include enough surrounding context that it doesn't look cherry-picked.>

## Developer hypothesis

<1-2 sentences: what looks suspicious based on what was found. Frame as
an observation or question, NOT as a diagnosis or fix.

GOOD: "The revision-advance logic in the sync loop and the channel
send seem tightly coupled — worth checking whether all send outcomes
are handled consistently."

GOOD: "The handle lifecycle in getHandle() under concurrent callers
looks like it could produce duplicates — the interplay between the
cache lookup and the creation path may not be fully synchronized."

GOOD: "The flag construction in the recovery-read path differs from
other read operations — the flag set may be incomplete for the
fencing protocol."

BAD: "The sync loop advances minRev even when the channel send fails,
causing dropped notifications." (names exact defect mechanism)

BAD: "The fix is to check the return value of the channel send and
only advance minRev on success." (prescribes the fix)

BAD: "The bug is in syncWatchers() at line 234 where minRev is set
unconditionally." (pinpoints exact line and defect)

BAD: "putIfAbsent return value is ignored, so the method uses a
locally created handle instead of the existing one." (names exact
root cause — someone can write the fix from this)

BAD: "Path A sets FLAG_X but path B does not." (contrast with
correct code makes the fix trivially derivable)

The hypothesis should make someone say "hmm, that's worth investigating
further" — not "ah, I know exactly what to fix." A good test: could
someone write the fix from ONLY the hypothesis, without reading any
source code? If yes, it's too specific.

Note: identifying that an ordering or interaction COULD cause a problem
(deadlock, performance drop, data loss) is acceptable — as long as the
debug context does NOT reveal the exact correct ordering or the exact reason
WHY the current ordering is wrong. The reader still has to reason about
which reordering is correct and why. For example:

GOOD: "The three disk-write operations in this handler have ordering
dependencies that could matter during crash recovery."
(reader must figure out which order is safe and why)

BAD: "Step A must happen before Step B because otherwise a crash
between them leaves the epoch updated but transactions uncommitted."
(reveals the exact crash window and the correct ordering)>
```

**Key rules for code investigation:**
- The `What was found` section must contain real command output (grep -n, sed -n, cat showing line numbers) run inside the container. Not hand-written code snippets.
- The hypothesis must be **one step removed from the root cause**. It identifies a suspicious area or pattern, not the exact bug. Think "this area looks relevant" not "this is the bug." Name the *subsystem* or *interaction*, not the *defect*.
- **NEVER contrast buggy code with correct code.** Do not show "path A does X but path B doesn't" — this makes the fix trivially derivable. Show only the code in the area the symptom points to and let the reader discover what's missing or wrong by reading the surrounding codebase themselves.
- **NEVER name the exact missing operation, flag, call, or field** in the hypothesis. Instead of "does not call `foo()` after `bar()`", write "the lifecycle of X in this function may be incomplete."
- **NEVER trace the full causal chain** from trigger to symptom. Stop at "this code is in the path of the symptom" — don't explain exactly how it produces the bug step-by-step.
- Include enough surrounding context in "What was found" that it doesn't look cherry-picked. Show 20-40 lines, not just the 3 lines around the defect.
- A case can have both runtime context AND code investigation. Runtime is always preferred; code investigation supplements it or covers cases where runtime context is hard to obtain.
- Code investigation is especially useful for logic bugs, protocol errors, and ordering issues that are visible in source but hard to trigger at runtime without injected tests.

---

## Procedure

### Step 1: Read case materials (symptom-only — NO solution)

For the target case, read these files in parallel:

```
cases/<case-name>/symptom.md
cases/<case-name>/reproduce.md
cases/<case-name>/verification.md
cases/<case-name>/case.yaml
```

**DO NOT read `cases-solution/<case-name>/solution.md` at this stage.** The solution is read ONLY in Step 6 (anti-leak checks) AFTER debug context is already drafted. Reading the solution before investigating contaminates your reasoning — you will unconsciously reverse-engineer "debug context" from the known answer, producing files that name the exact root cause instead of pointing at the problem area.

From these, understand:
- **What the developer observes** (symptom.md) — this is your starting point
- **What kind of bug** this is (crash, hang, data loss, race, logic error)
- **What language/project** and what tools are natural
- **What reproduce.sh does** — specifically, does it inject test files? (If yes, you cannot use those tests)

If `cases/<case-name>/context/` already exists and `--refresh` was not passed, report what's there and skip unless files look incomplete.

### Step 2: Plan your investigation

Think like a developer who just read the symptom description. What would you do first?

**Read `reproduce.sh` as a guardrail** — not to run it, but to understand whether it injects files. If it does, those files are off-limits for debug-context generation.

Then plan your debugging approach based on the bug category:

| Bug Category | Runtime Investigation | Code Investigation |
|---|---|---|
| **Crash** (segfault, SIGABRT, panic) | Run binary with triggering input, GDB/ASAN backtrace | Read crash handler, trace the call path from the stack trace |
| **Hang / Deadlock** | Thread/goroutine dump, jstack, GDB `thread apply all bt` | Search for lock ordering, channel operations, missing unlocks |
| **Data loss / Corruption** | Server + CLI to reproduce scenario, check logs | Trace the write/read path, look for missing persistence steps |
| **Race condition** | `go test -race`, TSAN, stress runs (`-count=10`) | Search for shared state accessed without synchronization |
| **Stale read / Linearizability** | Server + concurrent read/write via CLI | Trace the caching/buffering layer for stale state |
| **Logic error** | Run existing tests in the affected module, CLI/API | Read the logic in the area the symptom points to, note suspicious branches |
| **Resource leak** | Monitor goroutine/fd/memory count over time | Search for acquire-without-release patterns |
| **Election / Liveness** | Start cluster, trigger scenario, observe logs | Read state machine handlers, look for missing transitions |

### Step 3: Enter the container at the clean buggy commit

```bash
./bench.sh setup <case-name>
./bench.sh shell <case-name>
```

`bench.sh shell` drops you into the container at `/workspace/worktrees/<case>/` with the source at the buggy commit. No files have been injected. This is exactly what the agent sees.

If the workspace has been modified by a previous `reproduce.sh` run, reset first:

```bash
./bench.sh reset <case-name>
```

### Step 4: Investigate and capture debug context

Now you are inside the container. Act as a developer investigating the symptom.

**General approach:**
1. Look at what's available — built binaries, existing tests, server configs
2. Try to reproduce or observe the symptom using only what's there
3. Run debugging tools to gather clues
4. Capture raw output

**Example investigation strategies by project type:**

**C++ server (Dragonfly, Kvrocks, ClickHouse, RocksDB):**
```bash
# Start the server
./build-dbg/dragonfly --port 6379 --logtostderr &
# or
./build/kvrocks -c kvrocks.conf &

# Trigger the symptom via CLI
redis-cli -p 6379 <commands from symptom description>

# If it crashes, restart under GDB
gdb --batch -ex run -ex bt -ex "thread apply all bt" --args ./build-dbg/dragonfly --port 6379

# Or run with ASAN build if available
ASAN_OPTIONS=detect_leaks=1 ./build-asan/dragonfly --port 6379
```

**Go server (etcd, NATS, Consul, Raft):**
```bash
# Run existing tests in the affected package
go test -v -timeout 120s ./server/storage/mvcc/
go test -race -count=5 ./server/...

# Start the server and trigger via CLI
./bin/etcd &
etcdctl put key value
etcdctl watch key

# Goroutine dump of a hung process
kill -SIGQUIT <pid>
```

**Java/Scala (Kafka, BookKeeper, ZooKeeper):**
```bash
# Run existing tests in the affected module
mvn -pl bookkeeper-server test -Dtest="ExistingTestClass"
./gradlew :core:test --tests "kafka.server.ExistingTest"

# Start the server and trigger via CLI
bin/zookeeper-server-start.sh config/zookeeper.properties &
bin/zkCli.sh

# Thread dump of running JVM
jstack <pid>
```

**Erlang (RabbitMQ, Ra):**
```bash
# Run existing test suites
rebar3 ct --suite=existing_SUITE
make ct

# Start the node and trigger via CLI
rabbitmqctl <commands>
```

**Rust (raft-rs):**
```bash
# Run existing tests in the affected module
cargo test --lib test_module_name
cargo test -- --nocapture existing_test_name
```

**Capture everything to a raw file:**
```bash
<command> 2>&1 | tee /tmp/context-raw-<case-name>.txt
```

**What to capture (runtime):**
- The output that shows the symptom or a clue toward it
- If existing tests fail or behave unexpectedly — that's debug context
- If the server crashes with a backtrace — that's debug context
- If logs show anomalous behavior during the scenario — that's debug context
- If the race detector fires on existing tests — that's debug context
- If a thread/goroutine dump shows suspicious blocking — that's debug context
- Even negative results can be debug context (e.g., "existing test passes but under `-race` it panics")

**What to capture (code investigation):**
- After runtime investigation, read the source code in the area the symptom points to
- Use `grep -n`, `sed -n`, `cat -n` to capture relevant code sections with line numbers
- Note suspicious patterns: missing error checks, unconditional overwrites, unsynchronized access, missing branches
- Frame observations as hypotheses, not conclusions
- A case can have BOTH runtime context files AND a code investigation file

### Step 5: Write debug-context files

Create `cases/<case-name>/context/` and write files using ONLY content from the captured output.

The file must follow the format in the "Debug-Context File Format" section above. Every line in the `## Output` section must come from the captured raw output. You may trim for length but never add content.

The provenance line should read like:
- `Obtained by running go test -race -count=5 -timeout 120s ./server/storage/mvcc/`
- `Obtained by running gdb --batch -ex run -ex bt --args ./build/dragonfly --port 6379`
- `Obtained by running redis-cli -p 6379 EVALSHA "" 0`
- `Obtained by running mvn -pl bookkeeper-server test -Dtest="ExistingTestClass"`

NOT:
- `./bench.sh reproduce ...`
- `bash /bench/reproduce.sh`
- Any host path or bench.sh command
- Any command referencing an injected test file

**Verification gate:** After writing, re-read the debug-context file. Every non-trivial line under `## Output` must appear in `/tmp/context-raw-*.txt`. If any line doesn't, the file is fabricated — delete it.

### Step 6: Anti-leak checks (NOW read solution.md)

**This is the ONLY step where you read the solution.** Read `cases-solution/<case-name>/solution.md` now, then compare it against your drafted debug context to catch leaks. If you read the solution earlier, your debug context is likely contaminated — discard and re-investigate from the symptom.

Before finalizing, verify debug context does not leak the fix:

1. **Agent-reproducibility check**: Could an agent inside the container at `/workspace/worktrees/<case>/` (with only the buggy commit source, no injected files) actually run this exact command and get this output? If no, DELETE the debug-context file.

2. **Injected-test check**: Is this output from a test/file that was injected by reproduce.sh? If yes, DELETE the debug-context file.

2b. **Oracle-leak check**: Compare against `reproduce.sh` and `verification.md`. Does the file contain a verdict line, the oracle's messages, its thresholds, windows, or data sizes, or its exact trigger recipe? If yes, DELETE it and re-capture with your own scenario.

3. **Native output test**: Every line under `## Output` must be something the tool actually produced. No annotations, no decoded constants, no source-derived commentary.

4. **Fix-from-context test (CRITICAL)**: Could someone read ONLY this debug-context file and know exactly which function/line to fix and what to change? If yes, the debug context is too specific — it has become a diagnosis, not a clue. Rewrite or DELETE.

   Common leak patterns to catch:
   - **Naming the exact defect**: "does NOT set `FLAG_X`", "return value is ignored", "field is never reset" → these are root cause statements, not hypotheses
   - **Contrasting buggy code with correct code**: showing "path A does X but path B doesn't" makes the fix trivially derivable (add X to path A) → show only the buggy path; let the reader discover the contrast
   - **Full causal chains**: explaining step-by-step how the bug manifests from trigger to symptom → stop at "this area is relevant to the symptom", don't explain exactly how it produces the bug
   - **Hypothesis that names the missing operation**: "this function doesn't call `foo()` after doing `bar()`" → rephrase as "the lifecycle of X in this function seems incomplete"

   For code investigation, apply this rewrite test: remove the hypothesis entirely and read only the "What was found" section. If the code snippets alone (without the hypothesis) already make the fix obvious, the debug context is cherry-picked — include more surrounding context or show a broader area.

5. **Curation test**: Does it look cherry-picked by someone who knows the answer? For runtime context, include realistic context (multiple threads in a dump, surrounding log lines), not just the smoking gun. For code investigation, show enough surrounding code that the suspicious part isn't isolated artificially.

6. **Term check**: Debug context must NOT contain variable names from the fix diff or internal constant names decoded from source. For code investigation, function names in the problem area are acceptable (the developer found them by searching), but the hypothesis must not name the exact missing call or flag that constitutes the fix.

7. **Grep test**: Could someone grep the codebase for terms in this debug context and land directly on the buggy function? For runtime context, redact unique identifiers. For code investigation, pointing at the right area is expected — but the hypothesis must not narrow it to the exact line.

8. **Solution comparison test**: Now that you have read solution.md, check: does your debug-context file essentially restate the solution's root cause in different words? If someone who read the debug context would arrive at the same diagnosis as solution.md without further code reading, the debug context leaks. Rewrite the hypothesis to be one step more abstract — name the *area* or *pattern*, not the *defect*.

### Step 7: Report

```
=== Debug context: <case-name> ===
Investigation approach: <what you did as a developer>
Files created:
  - context/<filename>.md — <tool used>
Leak checks: PASSED
Agent-reproducibility: VERIFIED
```

---

## Placeholders (when investigation yields nothing)

Use placeholders only when genuine investigation inside the container produced no useful debug context — NOT as a shortcut for skipping investigation.

```markdown
# <Context Type>

## Status: NOT YET CAPTURED — requires investigation

**Attempted:** <what you tried inside the container>
**Tool:** <exact command to run for future attempt>
**Expected output type:** <e.g., "ASAN heap-buffer-overflow report", "goroutine dump">
**Why not captured:** <e.g., "Bug requires precise interleaving that could not be triggered manually; existing tests all pass cleanly">
```

---

## Batch Mode (`/debug-context all`)

1. List all case directories
2. Skip cases that already have debug context (unless `--refresh`)
3. For each case, run the full procedure including investigation inside the container
4. Print summary:

```
=== Batch Debug-Context Report ===
Total: 62 | Already had debug context: N | Generated: M | Placeholders: P | Errors: K
```

---

## Debug-Context File Naming

| Context Type | Filename |
|---|---|
| GDB backtrace | `gdb-backtrace.md` |
| Goroutine dump | `goroutine-dump.md` |
| Java thread dump | `jstack-dump.md` |
| Server logs | `logs.md` |
| Race detector | `race-detector.md` |
| ASAN/TSAN | `sanitizer-output.md` |
| Test output (existing tests at the buggy commit only, never reproduce.sh) | `test-output.md` |
| Test failure | `test-failure.md` |
| Crash stderr | `crash-output.md` |
| Hang/timeout | `hang-timeout.md` |
| Metrics | `metrics.md` |
| CT failure (Erlang) | `ct-failure.md` |
| Code investigation | `code-investigation.md` |

---

## Common Mistakes to Avoid

1. **Running `reproduce.sh` as debug-context source**: This is the #1 mistake. `reproduce.sh` often injects test files from the fix commit that the agent doesn't have, and its output always leaks the oracle (trigger, thresholds, verdict). NEVER run `reproduce.sh` to generate debug context, and never write a `test-output.md` that mirrors its output. Always work from clean buggy commit state via `bench.sh shell`. For hangs or stalls: reproduce the symptom condition yourself, then capture a thread dump, `INFO`/status output, and logs.

2. **Using output from injected tests**: If `reproduce.sh` injects `TestFoo.java` or `test_bar_test.go`, the agent doesn't have that file. Debug context from running that test is invalid. Always check what exists at the buggy commit first.

3. **Analysis in runtime context files**: Runtime context files must contain only raw tool output. No interpretation, no "this shows that..." — just the provenance line and the output. Analysis belongs in code investigation files only, and even there it must be framed as a hypothesis, not a conclusion.

4. **Using `bench.sh` or host commands in debug context**: The agent works inside a container with only workspace code. Debug-context provenance must show commands a developer runs inside the workspace (`go test`, `gdb`, `mvn test`, `grep -n`, etc.) — never `bench.sh`, never host paths.

5. **Code investigation that names the root cause**: This is the #2 most common mistake (after #1). 70% of code investigation files in audits were found to leak the root cause. The leaks take subtle forms:
   - Naming the exact defect: "does NOT set `FLAG_X`", "return value is ignored", "`field` is never reset"
   - Contrasting buggy path with correct path: "path A calls `foo()` but path B doesn't"
   - Full causal chain: explaining step-by-step how the code leads from trigger to symptom
   - Hypothesis that prescribes the fix: "this function doesn't call `cleanup()` after `init()`"
   
   Instead, name the *area* and *pattern*: "The flag construction in recovery reads differs from other read operations" or "The handle lifecycle under concurrent access may not be fully synchronized." If the hypothesis would let someone write the fix without reading more code, it's a diagnosis, not a clue — rewrite it.

6. **Hand-written code snippets in code investigation**: The "What was found" section must contain actual command output (`grep -n`, `sed -n`, `cat -n`) run inside the container, not hand-copied or paraphrased code. This ensures the debug context is reproducible by the agent.

7. **Modifying symptom.md**: Never touch symptom.md. Debug context and symptoms are completely separate artifacts. Debug context is injected as system prompt at benchmark time — it is never referenced from symptom files.

8. **Skipping investigation for placeholders**: Placeholders are a last resort after genuine debugging inside the container. Don't skip investigation because it seems hard — a developer would try things. Even partial clues (a related test that's flaky under `-race`, suspicious log output during the scenario) are valuable.

9. **Language mismatch**: Use the right tool for the language:
   - **C++**: GDB, ASAN/TSAN, Valgrind
   - **Go**: goroutine dumps (SIGQUIT), `-race`, pprof, delve
   - **Java/Scala**: jstack, test runner output
   - **Erlang**: `rebar3 ct`, crash dumps, `erlang:process_info/2`
   - **Rust**: GDB/LLDB, ASAN/TSAN
