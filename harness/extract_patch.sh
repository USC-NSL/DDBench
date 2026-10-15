#!/usr/bin/env bash
# extract_patch.sh -- Extract a replayable patch from a case worktree after an
# agent (or a human) modified it. Run it BEFORE `bench.sh reset`.
#
# Usage: harness/extract_patch.sh <case-name> <output-dir>
#
# Writes to <output-dir>:
#   patch.diff           `git diff --binary` of the worktree against the buggy
#                        commit. Includes new untracked files, deletions, mode
#                        changes, commits the agent made on top of the buggy
#                        commit, and edits inside submodules (as paths under the
#                        submodule directory). Replay it with
#                        `bench.sh eval <case> --patch patch.diff`.
#   patch_stat.txt       `git diff --stat` of the same change
#   patch_numstat.txt    `git diff --numstat` of the same change
#   patch_metadata.json  files_changed, lines_added, lines_removed,
#                        patch_category, changed_files, skipped_files
#
# Never included: SYMPTOM.md, REBUILD.sh and context/ (written by bench.sh),
# gitignored files (build outputs), and new untracked files larger than
# DDBENCH_MAX_NEW_FILE bytes (default 1 MiB; listed in skipped_files).
#
# The diff is computed in a throwaway container with a temporary git index; the
# worktree, its index and its refs are not modified.
set -euo pipefail

HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CASES_ROOT="${DDBENCH_ROOT:-$(cd "$HARNESS_DIR/.." && pwd)}"
BENCH="$CASES_ROOT/bench.sh"
MAX_NEW_FILE="${DDBENCH_MAX_NEW_FILE:-1048576}"

[ $# -ge 2 ] || { echo "Usage: $0 <case-name> <output-dir>" >&2; exit 2; }
CASE_NAME="$1"
OUTPUT_DIR="$2"
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"

[ -d "$CASES_ROOT/cases/$CASE_NAME" ] || { echo "Case not found: $CASE_NAME" >&2; exit 2; }

# Opaque Docker names and the worktree path come from bench.sh.
VOL=$(bash "$BENCH" info "$CASE_NAME" volume)
IMAGE=$(bash "$BENCH" info "$CASE_NAME" image)
WT_PATH=$(bash "$BENCH" info "$CASE_NAME" workdir)
BASE_SHA=$(bash "$BENCH" info "$CASE_NAME" buggy_sha)
docker volume inspect "$VOL" >/dev/null 2>&1 || { echo "$CASE_NAME is not set up (no volume $VOL)" >&2; exit 2; }

STAGE=$(mktemp -d "${TMPDIR:-/tmp}/ddbench-extract.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
chmod 777 "$STAGE"

# shellcheck disable=SC2016  # runs inside the container
docker run --rm --network none \
    -v "${VOL}:/workspace" \
    -v "${STAGE}:/out" \
    -w "$WT_PATH" \
    -e "BASE_SHA=${BASE_SHA}" \
    -e "MAX_NEW_FILE=${MAX_NEW_FILE}" \
    "$IMAGE" \
    bash -c '
set -euo pipefail
git config --global --add safe.directory "*" 2>/dev/null || true
: >/out/patch.diff; : >/out/numstat; : >/out/stat; : >/out/skipped

# diff_tree <base-commit> <path-prefix> [extra pathspec...]
# Diff the working tree of the current repository against <base-commit>,
# untracked (non-ignored) files included, via a temporary index.
diff_tree() {
    local base="$1" prefix="$2"; shift 2
    local idx f size
    idx=$(mktemp)
    GIT_INDEX_FILE="$idx" git read-tree "$base"
    GIT_INDEX_FILE="$idx" git add -A --ignore-errors -- . "$@" 2>/dev/null || true
    # Skip large new files (typically build outputs that are not gitignored).
    while IFS= read -r -d "" f; do
        size=$(stat -c %s -- "$f" 2>/dev/null || echo 0)
        if [ "$size" -gt "$MAX_NEW_FILE" ]; then
            GIT_INDEX_FILE="$idx" git rm -q --cached -- "$f"
            printf "%s%s\t%s\n" "$prefix" "$f" "$size" >>/out/skipped
        fi
    done < <(GIT_INDEX_FILE="$idx" git diff --cached --name-only -z --diff-filter=A "$base")
    local opts=(--cached --no-color --no-ext-diff --ignore-submodules=all "--src-prefix=a/$prefix" "--dst-prefix=b/$prefix" "$base")
    GIT_INDEX_FILE="$idx" git diff --binary --full-index "${opts[@]}" >>/out/patch.diff
    GIT_INDEX_FILE="$idx" git diff --numstat "${opts[@]}" | awk -v p="$prefix" -F "\t" "{print \$1 \"\t\" \$2 \"\t\" p \$3}" >>/out/numstat
    GIT_INDEX_FILE="$idx" git diff --stat=200 "${opts[@]}" >>/out/stat
    rm -f "$idx"
}

# Superproject: everything except files written by bench.sh.
diff_tree "$BASE_SHA" "" ":(top,exclude)SYMPTOM.md" ":(top,exclude)REBUILD.sh" ":(top,exclude)context"

# Submodules: working tree against the commit the buggy superproject records.
if [ -f .gitmodules ]; then
    git ls-tree -r "$BASE_SHA" | awk "\$2 == \"commit\" {print \$3 \"\t\" \$4}" | \
    while IFS=$(printf "\t") read -r sha path; do
        [ -e "$path/.git" ] || continue
        ( cd "$path" && git cat-file -e "$sha^{commit}" 2>/dev/null && diff_tree "$sha" "$path/" ) || true
    done
fi
'

mv "$STAGE/patch.diff" "$OUTPUT_DIR/patch.diff"
mv "$STAGE/stat" "$OUTPUT_DIR/patch_stat.txt"
mv "$STAGE/numstat" "$OUTPUT_DIR/patch_numstat.txt"

python3 - "$OUTPUT_DIR/patch_numstat.txt" "$STAGE/skipped" "$OUTPUT_DIR/patch_metadata.json" "$BASE_SHA" <<'PYTHON'
import json, sys

numstat_file, skipped_file, output_file, base_sha = sys.argv[1:5]
files, added_total, removed_total = [], 0, 0
with open(numstat_file) as f:
    for line in f:
        parts = line.rstrip("\n").split("\t")
        if len(parts) < 3:
            continue
        added = int(parts[0]) if parts[0].isdigit() else 0   # "-" for binary files
        removed = int(parts[1]) if parts[1].isdigit() else 0
        added_total += added
        removed_total += removed
        files.append({"file": parts[2], "added": added, "removed": removed,
                      "binary": parts[0] == "-"})
skipped = []
with open(skipped_file) as f:
    for line in f:
        path, _, size = line.rstrip("\n").rpartition("\t")
        if path:
            skipped.append({"file": path, "bytes": int(size)})

n = len(files)
category = "empty" if n == 0 else "surgical" if n <= 2 else "moderate" if n <= 5 else "broad"
meta = {
    "base_commit": base_sha,
    "files_changed": n,
    "lines_added": added_total,
    "lines_removed": removed_total,
    "patch_category": category,
    "changed_files": files,
    "skipped_files": skipped,
}
with open(output_file, "w") as f:
    json.dump(meta, f, indent=2)
msg = f"Patch: {n} file(s), +{added_total}/-{removed_total}, {category}"
if skipped:
    msg += f"; skipped {len(skipped)} large new file(s)"
print(msg)
PYTHON
