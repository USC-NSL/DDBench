# Solution: PROJECT #ISSUE

## Fix
- **PR:** https://github.com/ORG/REPO/pull/PR_NUMBER
- **Commit:** `FIX_COMMIT_HASH`

## Fix locus
- **Component:** TODO: subsystem/module name (e.g., "transaction engine", "Raft snapshot", "subscription manager")
- **Files:** TODO: list files changed in the fix

## Root cause
TODO: 2-3 sentences explaining WHY the bug happens at a code level.

## Diagnosis chain
TODO: How would a debugger arrive at the root cause? Document the reasoning path:
1. What runtime evidence (crash output, logs, cluster behavior) points toward the component?
2. What code-level reasoning (invariant analysis, control flow tracing) narrows to the specific fault?
3. Where does the runtime observation and code analysis intersect to reveal the root cause?

## Fix description
TODO: 1-2 paragraphs explaining WHAT the fix changes.

## How to apply
```bash
git checkout FIX_COMMIT_HASH
TODO_BUILD_COMMAND
```

## How to verify
Run `./reproduce.sh` after applying the fix — it should output `PASS`.
