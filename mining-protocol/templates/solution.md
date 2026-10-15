# Solution: PROJECT #ISSUE

- **Issue:** https://github.com/ORG/REPO/issues/ISSUE
- **Fix commit:** `FIX_COMMIT_HASH` (PR: https://github.com/ORG/REPO/pull/PR_NUMBER)
- **Gold patch:** [`gold.patch`](gold.patch): the source-only part of the fix, applied by `./bench.sh validate-oracle`

## Fix locus
- **Component:** TODO: subsystem/module name (e.g., "transaction engine", "Raft snapshot", "subscription manager")
- **Files:** TODO: list the files changed in gold.patch

## Root cause
TODO: 2-3 sentences explaining WHY the bug happens at a code level.

## Diagnosis chain
TODO: How would a debugger arrive at the root cause? Document the reasoning path:
1. What runtime evidence (crash output, logs, cluster behavior) points toward the component?
2. What code-level reasoning (invariant analysis, control flow tracing) narrows to the specific fault?
3. Where does the runtime observation and code analysis intersect to reveal the root cause?

## Fix description
TODO: 1-2 paragraphs explaining WHAT the fix changes.

## How to verify
```bash
./bench.sh validate-oracle CASE_NAME --runs 3   # buggy worktree FAILs, gold.patch PASSes -> SOUND
./bench.sh eval CASE_NAME --patch cases-solution/CASE_NAME/gold.patch   # score the gold patch alone
```
