# /newcase — Interactive Case Scaffolder

Scaffold a new benchmark case from templates and validate it against the mining protocol's selection criteria.

## Usage

```
/newcase <project>-<issue#>-<slug>
```

## Procedure

### Step 1: Parse and validate the case name

Extract `<project>`, `<issue#>`, and `<slug>` from the argument.

Validate:
- Name matches pattern: `<project>-<number>-<slug>` (lowercase, hyphen-separated)
- Slug is 2-4 words
- Case directory does not already exist

### Step 2: Scaffold directories and files

```bash
CASE="<case-name>"
cp -r mining-protocol/templates/ "cases/$CASE/"
mkdir -p "cases-solution/$CASE/"
cp mining-protocol/templates/solution.md "cases-solution/$CASE/solution.md"
mkdir -p ".devcontainer/$CASE/"
cp mining-protocol/templates/devcontainer.json ".devcontainer/$CASE/devcontainer.json"
chmod +x "cases/$CASE/setup.sh" "cases/$CASE/reproduce.sh"
```

### Step 3: Replace placeholders

In all scaffolded files, replace the following placeholders with actual values:
- `CASE_NAME` → the full case name
- `PROJECT` → the project name
- `ISSUE` → the issue number
- `ORG/REPO` → the GitHub org/repo (ask the user)
- `LANGUAGE` → the language (ask the user)

Do NOT replace `TODO_*` or `FIX_COMMIT*` placeholders — those require the user's input.

### Step 4: Gatekeeping tests (interactive)

Walk the user through the three gatekeeping tests from the mining protocol. Ask these questions and wait for answers:

**1. Dual-reasoning test:**
> Can this bug be diagnosed from a stack trace or error log alone? (If yes, it may be too shallow.)
> Can this bug be diagnosed from reading the code without running the system? (If yes, it's a purely static bug.)

**2. Fix locus test:**
> What component/subsystem does the fix live in?
> Which files are changed in the fix? (Ideally 1-3 files.)

**3. Issue text test:**
> Does the GitHub issue describe the root cause and fix location explicitly?
> (If an agent could derive the patch just by reading the issue, the case bypasses diagnosis.)

If any test fails, warn the user and explain why the case may not be suitable. Do not block — the user may override.

### Step 5: Docker check

Check if `docker/<project>.Dockerfile` exists:
- If yes: report "Dockerfile exists, no Docker work needed."
- If no: warn "No Dockerfile for project '<project>'. You'll need to create one — see mining-protocol/authoring-guide.md Phase 3."

Also check if the project appears in any existing `case.yaml`:
- If yes: report "Project '<project>' has N existing cases — Docker image is already tested."
- If no: flag this as a new project and remind to update CLAUDE.md.

### Step 6: Summary

Print a summary of what was created and what the user needs to fill in:

```
=== Case scaffolded: <case-name> ===

Created:
  cases/<case-name>/          (8 files from template)
  cases-solution/<case-name>/ (solution.md)
  .devcontainer/<case-name>/  (devcontainer.json)

Next steps:
  1. Fill in case.yaml with repo URL, fix commit, build command
  2. Write symptom.md (observable behavior only — no leakage!)
  3. Write reproduce.md with exact reproduction steps
  4. Write verification.md with oracle logic
  5. Implement setup.sh host fallback
  6. Implement reproduce.sh host fallback
  7. Write setup.md for human readers
  8. Complete README.md
  9. Write solution.md with fix locus and diagnosis chain
  10. [If new project] Create docker/<project>.Dockerfile

Run /sanitize <case-name> before merging to check for leakage.
Run /verify-oracle <case-name> after scripts are ready.
```
