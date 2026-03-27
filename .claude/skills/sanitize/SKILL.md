# /sanitize — Symptom File Leakage Scanner

Scan symptom files for information leakage by cross-referencing against solution files. Auto-fix violations and report what was changed.

## Usage

```
/sanitize              # scan all cases
/sanitize <case-name>  # scan a specific case
```

## Procedure

### Step 1: Build the reference set

For each case (or the specified case):
1. Read `cases-solution/<case-name>/solution.md`
2. Extract:
   - Function and method names mentioned in "Root cause", "Fix description", and "Diagnosis chain"
   - Variable, struct field, and constant names
   - File paths listed in "Fix locus" → "Files"
   - The component name from "Fix locus" → "Component"
   - PR numbers and commit hashes from "Fix"

Store these as the **prohibited terms** for that case.

### Step 2: Scan symptom files

For each case, read `cases/<case-name>/symptom.md` and check for:

| Check | How |
|-------|-----|
| Function/method names from fix | Grep for each extracted name (case-sensitive) |
| Variable/field names from fix | Grep for each extracted name |
| File paths from fix | Grep for directory or filename fragments |
| Internal constants/magic numbers | Grep for hex values, error codes, or constants from the fix diff |
| Fix strategy descriptions | Look for phrases like "make X idempotent", "add synchronization", "check for null", "handle the case where" |
| Root cause mechanism | Look for causal language pointing to code ("the function fails to", "X is called after Y", "the field is not initialized") |
| Error messages from source only | Compare error strings in symptom against user-facing error strings (OK) vs source-only strings (leak) |
| PR/commit references | Grep for PR numbers, commit hashes |

### Step 3: Report

For each file scanned, output a table:

```
## <case-name>

| Status | Violation | Line | Prohibited term | Suggested rewrite |
|--------|-----------|------|-----------------|-------------------|
| LEAK   | Function name | 3 | `ChangeMonitor` | "Calling MONITOR twice" |
| CLEAN  | — | — | — | — |
```

### Step 4: Auto-fix (if violations found)

For each violation:
1. Rewrite the offending sentence to describe only observable behavior
2. Show a before/after diff
3. Apply the edit

### Step 5: Verify the fix

Re-run the scan on the edited file to confirm zero violations remain.

### Output format

```
=== Sanitize Report ===
Scanned: N cases
Clean: M cases
Violations found and fixed: K cases
  - <case-name>: N violations (function name, file path, ...)
  - <case-name>: N violations (...)

Remaining violations: 0
```

## Anti-patterns to watch for

These are subtle leaks that are easy to miss:

- **Indirect function references**: "the monitor registration logic" (hints at ChangeMonitor)
- **Overly specific error messages**: "`Check failed: cc_`" (only visible in source code)
- **Architectural hints**: "the subscription cleanup path" (names the component)
- **Conditional leaks**: "works fine with one MONITOR but not two" is OK (observable), but "the second call adds a duplicate entry" is a leak (describes the mechanism)

## Litmus test

After rewriting, ask: "Could an agent `grep` the codebase using terms from this symptom file and land on the fix location?" If yes, it still leaks.
