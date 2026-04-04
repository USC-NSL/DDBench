# Benchmark Case Information Triage

## The Insight

When authoring bug case documentation for agent benchmarks, information leakage is not just lexical (exact function names, file paths) — it's **semantic**. A symptom file can hand an agent the entire diagnosis without using a single prohibited term, by describing the internal mechanism in natural language. The key is to classify every piece of information by **how it was obtained**, not by what words it uses.

## Why This Matters

If symptom files contain semantic leaks, benchmark results are inflated — agents appear to "debug" when they're really just pattern-matching the diagnosis handed to them. The ZooKeeper #4925 case demonstrated this: the symptom file named `committedLog`, referenced `ZOOKEEPER-4394`, and described the exact `processTxn` variant issue — all in "symptom" language. An agent could produce the fix without reading a single line of source code.

## Recognition Pattern

This skill applies when:
- Authoring or reviewing `symptom.md` files for ddbench cases
- Running `/sanitize` on new or existing cases
- Any sentence in a symptom file makes you think "that's basically the root cause"
- A symptom file uses internal terminology (data structure names, protocol phase names, function behavior descriptions) even if those terms aren't in the solution file

## The Approach

Use the **Three-Tier Information Funnel** — classify by acquisition method, not by content:

1. **Tier 1 (symptom.md)**: Could an operator observe this by just running the software? Keep.
2. **Tier 2 (evidence/)**: Could a developer obtain this with runtime tools (logs, debugger, strace) WITHOUT reading source? Extract — but sanitize to not reveal the fix.
3. **Tier 3 (redact)**: Would you need to read the source code to know this? Remove entirely.

The critical heuristic: **"Could this sentence have been written by someone who never opened the source code?"** If no, it doesn't belong in symptom.md.

The critical boundary between Tier 2 and Tier 3: **Evidence shows WHAT is happening at runtime. Diagnosis explains WHY.** A goroutine dump showing a blocked channel is evidence. Explaining which function should have sent on that channel is diagnosis.

## Edge case: already-clean symptoms with missing evidence

Some cases (e.g., raft-268 deadlock) have perfectly clean symptom files ("it hangs") but no evidence directory. The three-tier model also works in reverse: when a symptom is clean but sparse, consider whether Tier 2 evidence should be **added** to make the benchmark more realistic. A real developer investigating "it hangs" would capture a goroutine dump — providing that (sanitized) gives the agent a realistic starting point without leaking the fix.

For HANG oracle types: goroutine/thread dumps are natural Tier 2 evidence.
For CRASH oracle types: stack traces and core dump backtraces are natural Tier 2 evidence.
For OUTPUT oracle types: diff of expected vs actual output is natural Tier 2 evidence.
For METRIC oracle types: time-series graphs or counter snapshots are natural Tier 2 evidence.

## Example

**Before (leaks):**
> "After DIFF sync, the follower's `committedLog` has a hole because `processTxn(TxnHeader, Record)` doesn't call `addCommittedProposal()`. This is a regression from ZOOKEEPER-4394."

**After (clean symptom.md):**
> "After a follower that was offline rejoins and later becomes leader, clients discover that previously committed znodes are missing. Only affects ZooKeeper 3.9.3+."

**After (evidence/logs.md):**
> Server log showing sync type selection during rejoin, absence of errors despite data loss.
