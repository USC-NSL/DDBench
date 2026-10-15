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

Ask the user which reproduce template fits the bug (see `mining-protocol/templates/README.md`; default: the generic `reproduce.sh`). Copy each template to its own destination, never the templates directory wholesale:

```bash
CASE="<case-name>"; PROJECT="<project>"; VARIANT="<reproduce template>"
T=mining-protocol/templates
mkdir -p "cases/$CASE" "cases-solution/$CASE" ".devcontainer/$CASE"
cp "$T/case.yaml" "$T/symptom.md" "$T/reproduce.md" "cases/$CASE/"
cp "$T/case-README.md" "cases/$CASE/README.md"
cp "$T/$VARIANT" "cases/$CASE/reproduce.sh"
chmod +x "cases/$CASE/reproduce.sh"
cp "$T/solution.md" "cases-solution/$CASE/solution.md"
CASE_UID=$(printf %s "$CASE" | sha256sum | cut -c1-12)    # same as: ./bench.sh info "$CASE" uid
sed -e "s/CASE_NAME/$CASE/g" -e "s/PROJECT/$PROJECT/g" -e "s/CASE_UID/$CASE_UID/g" \
    "$T/devcontainer.json" > ".devcontainer/$CASE/devcontainer.json"
```

There is no per-case setup script or setup document: `case.yaml` is the declarative spec and `./bench.sh setup <case>` is the only setup entry point. `gold.patch` has no template; the user writes it later (see the next steps in Step 6).

### Step 3: Replace placeholders

In the scaffolded `case.yaml`, `*.md` and `solution.md` files, replace the following placeholders with actual values:
- `CASE_NAME` → the full case name
- `PROJECT` → the project name
- `ISSUE` → the issue number
- `ORG/REPO` → the GitHub org/repo (ask the user)
- `LANGUAGE` → the language (ask the user)

In `reproduce.sh`, replace only `<case-name>`. Never substitute `CASE_NAME` there: the standard prelude uses a shell variable of that name.

Do NOT replace `TODO_*`, `FIX_COMMIT*`, `ORACLE_TEST_NAME`, `GO_*` or `*_ITERATIONS` placeholders — those require the user's input.

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
  cases/<case-name>/          (case.yaml, reproduce.sh, symptom.md, README.md, reproduce.md)
  cases-solution/<case-name>/ (solution.md)
  .devcontainer/<case-name>/  (devcontainer.json)

Next steps:
  1. Fill in case.yaml: repo URL, buggy_commit / fix_commit, resolve_time, build command, num_cpus
  2. Write symptom.md (observable behavior only — no leakage!)
  3. Write reproduce.md with exact reproduction steps (run inside ./bench.sh shell)
  4. Implement reproduce.sh after its prelude (exit 0 PASS / 1 FAIL / 2 ERROR; injected tests named DDBenchOracle*),
     then fill in the "Oracle verdict" section of reproduce.md (what FAIL/PASS/ERROR mean)
  5. Complete README.md
  6. Write solution.md with fix locus and diagnosis chain, and gold.patch (source-only fix diff)
  7. Fill in TODO_EXTENSIONS in .devcontainer/<case-name>/devcontainer.json
  8. [If new project] Create docker/<project>.Dockerfile
  9. ./bench.sh setup <case-name> && ./bench.sh reproduce <case-name>   (expect FAIL)
  10. ./bench.sh validate-oracle <case-name> --runs 3                     (expect SOUND)
  11. [Optional] /debug-context <case-name> to write context/

Run /sanitize <case-name> before merging to check for leakage.
Run /verify-oracle <case-name> after scripts are ready.
```
