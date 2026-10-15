# Bug Case Mining Protocol

This directory formalizes the end-to-end process for adding a new verified bug case to DDBench. Every case must be **self-contained**: on any machine with Docker, a fresh clone of this repository must give a deterministic verdict from `./bench.sh setup <case>` followed by `./bench.sh reproduce <case>`, with zero manual intervention. Everything runs in Docker through `bench.sh`; there is no host mode.

## Protocol Documents

| Document | Purpose |
|----------|---------|
| [selection-criteria.md](selection-criteria.md) | What makes a bug eligible for this benchmark |
| [case-anatomy.md](case-anatomy.md) | Every file a case requires, with format specifications and the reproduce.sh contract |
| [docker-containment.md](docker-containment.md) | Images, volumes, containment, offline scoring, agent isolation |
| [authoring-guide.md](authoring-guide.md) | Step-by-step walkthrough for adding a new case (including authoring `context/`) |
| [checklist.md](checklist.md) | Pre-merge validation checklist |
| [templates/](templates/) | Skeleton files, each copied to its own destination |

## Quick Start

```bash
CASE=<project>-<issue#>-<slug>        # e.g. raft-358-negative-log-range
PROJECT=<project>                     # must match docker/<project>.Dockerfile
VARIANT=reproduce-server-crash.sh     # the reproduce template that fits (templates/README.md)
T=mining-protocol/templates

# 1. Case files: only these go into cases/<case>/
mkdir -p "cases/$CASE"
cp "$T/case.yaml" "$T/symptom.md" "$T/reproduce.md" "cases/$CASE/"
cp "$T/case-README.md" "cases/$CASE/README.md"
cp "$T/$VARIANT" "cases/$CASE/reproduce.sh"
chmod +x "cases/$CASE/reproduce.sh"

# 2. Solution files, outside cases/ (never mounted into any container)
mkdir -p "cases-solution/$CASE"
cp "$T/solution.md" "cases-solution/$CASE/solution.md"
#    ...and write cases-solution/$CASE/gold.patch (see case-anatomy.md §8)

# 3. Dev container config (after case.yaml is filled in; renders templates/devcontainer.json's
#    layout for every case, adding the case's caps/seccomp and the project's VS Code extensions)
python3 scripts/generate_devcontainers.py

# 4. Case name and project. Not CASE_NAME in reproduce.sh: its prelude uses a shell
#    variable of that name, so the reproduce templates write the case name as <case-name>.
sed -i -e "s/CASE_NAME/$CASE/g" -e "s/PROJECT/$PROJECT/g" \
    "cases/$CASE"/*.md "cases/$CASE/case.yaml" "cases-solution/$CASE/solution.md"
sed -i "s/<case-name>/$CASE/g" "cases/$CASE/reproduce.sh"

# 5. Fill in the remaining placeholders and TODOs (templates/README.md lists them), then
#    add a Dockerfile if this is a new project (docker-containment.md).

# 6. Validate (checklist.md has the full pre-merge list)
./bench.sh setup "$CASE"                         # warm-up should report FAIL on the buggy code
./bench.sh reproduce "$CASE"                     # expect exit 1 / "FAIL: ...", no trigger errors in the output
./bench.sh validate-oracle "$CASE" --runs 3      # buggy FAILs and gold.patch PASSes every run -> SOUND
```

Exit codes everywhere: 0 PASS, 1 FAIL, 2 ERROR. `/verify-oracle <case>` adds the semantic
checks (the FAIL has the right cause, negative control for metric oracles, fix-specific
anti-patterns); `/newcase` and `/mine` automate the scaffolding.
