# Bug Case Mining Protocol

This directory formalizes the end-to-end process for adding a new verified bug case to the benchmark suite. Every case must be **self-contained**: a fresh machine with Docker (or Ubuntu 24.04) should be able to clone this repo, run two scripts, and get a deterministic PASS/FAIL verdict with zero manual intervention.

## Protocol Documents

| Document | Purpose |
|----------|---------|
| [selection-criteria.md](selection-criteria.md) | What makes a bug eligible for this benchmark |
| [case-anatomy.md](case-anatomy.md) | Every file a case requires, with format specifications |
| [docker-containment.md](docker-containment.md) | Why and how each case is Docker-self-contained |
| [authoring-guide.md](authoring-guide.md) | Step-by-step walkthrough for adding a new case |
| [checklist.md](checklist.md) | Pre-merge validation checklist |
| [templates/](templates/) | Skeleton files to copy when starting a new case |

## Quick Start

```bash
# 1. Copy templates into a new case directory
cp -r mining-protocol/templates/ cases/<project>-<issue#>-<slug>/

# 2. Fill in every file following case-anatomy.md
# 3. Create solution file
mkdir -p cases-solution/<project>-<issue#>-<slug>/
# Write solution.md (kept separate to avoid leaking answers)

# 4. Add Docker support if this is a new project
# See docker-containment.md for Dockerfile requirements

# 5. Validate
# See checklist.md for the full pre-merge checklist
./bench.sh setup <case-name> && ./bench.sh reproduce <case-name>
# Expect: FAIL (bug is present on the buggy commit), with no trigger errors in the output
# Then: /verify-oracle <case-name>. It checks that the FAIL has the right cause and that
#       the hash-verified fix tree PASSes, over repeated runs. Exit codes: 0 PASS, 1 FAIL, 2 ERROR.
```
