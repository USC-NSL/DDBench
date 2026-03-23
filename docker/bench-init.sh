#!/usr/bin/env bash
# bench-init.sh — Runs INSIDE a container to initialize a case's worktree and build.
# Called by devcontainer postCreateCommand or manually by users.
# Usage: bench-init.sh <case-name>
set -euo pipefail

CASE_NAME="${1:?Usage: bench-init.sh <case-name>}"
REPO_DIR="/repo"
YAML="$REPO_DIR/cases/$CASE_NAME/case.yaml"
WORKSPACE="/workspace"
WT_PATH="$WORKSPACE/worktrees/$CASE_NAME"

[ -f "$YAML" ] || { echo "ERROR: $YAML not found"; exit 1; }

# ── Minimal YAML parser (same logic as bench.sh) ────────────────────────────

yaml_val() {
    local file="$1" key="$2"
    grep -m1 "^${key}:" "$file" 2>/dev/null | sed "s/^${key}:[[:space:]]*//" | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/"
}

yaml_nested() {
    local file="$1" parent="$2" key="$3"
    awk -v p="$parent" -v k="$key" '
        BEGIN { in_parent=0; found_key=0; printed=0 }
        $0 ~ "^"p":" { in_parent=1; next }
        in_parent && /^[^ \t]/ { in_parent=0 }
        in_parent && $0 ~ "^  "k":" {
            line = $0; sub("^  "k":[ ]*", "", line)
            gsub(/^["'"'"']|["'"'"']$/, "", line)
            if (line == "|" || line == "|-" || line == ">" || line == ">-") { found_key=1; next }
            print line; printed=1; exit
        }
        found_key && /^    / { line=$0; sub("^    ","",line); if(result!="")result=result"\n"; result=result line; next }
        found_key && !/^    / { print result; printed=1; exit }
        END { if (!printed && found_key && result != "") print result }
    ' "$file"
}

# ── Read case metadata ──────────────────────────────────────────────────────

REPO_URL=$(yaml_val "$YAML" "repo")
COMMIT=$(yaml_val "$YAML" "buggy_commit")
SUBMODULES=$(yaml_val "$YAML" "submodules")
BUILD_CMD=$(yaml_nested "$YAML" "build" "command")

echo "=== bench-init: $CASE_NAME ==="
echo "  Repo:    $REPO_URL"
echo "  Commit:  $COMMIT"
echo ""

# ── Step 1: Clone repo into workspace (if not already cloned) ───────────────

if [ ! -d "$WORKSPACE/.git" ]; then
    echo "Cloning $REPO_URL ..."
    CLONE_ARGS=(--no-checkout)
    [ "$SUBMODULES" = "true" ] && CLONE_ARGS+=(--recurse-submodules)
    git clone "${CLONE_ARGS[@]}" "$REPO_URL" /tmp/_clone
    mv /tmp/_clone/.git "$WORKSPACE/.git"
    rm -rf /tmp/_clone
else
    echo "Repository already cloned."
fi

# ── Step 2: Create worktree for this case ────────────────────────────────────

if [ ! -d "$WT_PATH" ]; then
    echo "Creating worktree at $WT_PATH ..."
    cd "$WORKSPACE"
    git fetch --all 2>/dev/null || true
    RESOLVED=$(git rev-parse "$COMMIT" 2>/dev/null || echo "$COMMIT")
    mkdir -p "$WORKSPACE/worktrees"
    git worktree add --detach "$WT_PATH" "$RESOLVED"
    if [ "$SUBMODULES" = "true" ]; then
        cd "$WT_PATH"
        git submodule update --init --recursive
    fi
else
    echo "Worktree already exists."
fi

# ── Step 3: Build ────────────────────────────────────────────────────────────

if [ -n "$BUILD_CMD" ]; then
    echo "Building ..."
    cd "$WT_PATH"
    eval "$BUILD_CMD"
fi

echo ""
echo "=== bench-init complete: $CASE_NAME ==="
echo "  Source: $WT_PATH"
