#!/usr/bin/env bash
# bench.sh — Central orchestrator for bug-bench Docker-based isolation
# Usage:
#   bench.sh setup <case-name>       Build image + clone + checkout + build
#   bench.sh reproduce <case-name>   Run reproduce.sh inside container
#   bench.sh shell <case-name>       Interactive shell inside container
#   bench.sh clean <case-name>       Remove container + volumes for this case
#   bench.sh clean-all               Remove all bug-bench containers + volumes + images
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_PREFIX="bug-bench"

# Global array populated by build_run_args, consumed by Docker commands.
RUN_ARGS=()

# ── Helpers ──────────────────────────────────────────────────────────────────

die() { echo "ERROR: $*" >&2; exit 1; }

require_cmd() {
    command -v "$1" &>/dev/null || die "$1 is required but not found. Please install it."
}

# ── YAML Parsing (pure bash, no yq dependency) ──────────────────────────────
# NOTE: case.yaml files MUST use exactly 2-space indentation and inline list
# syntax (e.g., caps: ["NET_ADMIN"]). Block sequences (- item) are not supported.

# Parse top-level "key: value" from YAML.
# Strips surrounding quotes. Returns empty string if key not found.
yaml_val() {
    local file="$1" key="$2"
    local line
    line=$(grep -m1 "^${key}:" "$file" 2>/dev/null || echo "")
    [ -z "$line" ] && return 0
    local val
    val=$(echo "$line" | sed "s/^${key}:[[:space:]]*//" | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/")
    echo "$val"
}

# Parse a nested "parent.key" value from YAML.
# Handles both inline values and YAML block scalars (|, >).
yaml_nested() {
    local file="$1" parent="$2" key="$3"
    awk -v p="$parent" -v k="$key" '
        BEGIN { in_parent=0; found_key=0; printed=0 }

        # Match parent block start
        $0 ~ "^"p":" { in_parent=1; next }
        # Exit parent block on unindented line
        in_parent && /^[^ \t]/ { in_parent=0 }

        # Match key within parent
        in_parent && $0 ~ "^  "k":" {
            line = $0
            sub("^  "k":[ ]*", "", line)
            # Strip surrounding quotes
            gsub(/^["'"'"']|["'"'"']$/, "", line)

            # Check for block scalar indicator
            if (line == "|" || line == "|-" || line == ">" || line == ">-") {
                found_key = 1
                next
            }
            # Inline value
            print line
            printed = 1
            exit
        }

        # Collect block scalar lines (indented more than key level)
        found_key && /^    / {
            line = $0
            sub("^    ", "", line)
            if (result != "") result = result "\n"
            result = result line
            next
        }

        # End of block scalar
        found_key && !/^    / {
            print result
            printed = 1
            exit
        }

        END {
            if (!printed && found_key && result != "") print result
        }
    ' "$file"
}

find_case_dir() {
    local case_name="$1"
    local case_dir="$REPO_ROOT/cases/$case_name"
    [ -d "$case_dir" ] || die "Case directory not found: $case_dir"
    echo "$case_dir"
}

find_case_yaml() {
    local case_dir="$1"
    local yaml="$case_dir/case.yaml"
    [ -f "$yaml" ] || die "case.yaml not found in $case_dir. Is this case configured for Docker?"
    echo "$yaml"
}

# ── Image Management ─────────────────────────────────────────────────────────

ensure_base_image() {
    local base="$1"
    local dockerfile="$REPO_ROOT/docker/${base}.Dockerfile"
    local tag="${IMAGE_PREFIX}/${base}"

    [ -f "$dockerfile" ] || die "Dockerfile not found: $dockerfile"

    if ! docker image inspect "$tag" &>/dev/null; then
        echo "Building base image: $tag ..."
        docker build -t "$tag" -f "$dockerfile" "$REPO_ROOT/docker"
    fi
}

ensure_project_image() {
    local project="$1"
    local dockerfile="$REPO_ROOT/docker/${project}.Dockerfile"
    local tag="${IMAGE_PREFIX}/${project}"

    [ -f "$dockerfile" ] || die "Dockerfile not found: $dockerfile"

    # Determine base image from Dockerfile's FROM line
    local from_image
    from_image=$(grep -m1 '^FROM' "$dockerfile" | awk '{print $2}')

    # Build base image if it's one of ours
    case "$from_image" in
        ${IMAGE_PREFIX}/base-cpp) ensure_base_image "base-cpp" ;;
        ${IMAGE_PREFIX}/base-go)  ensure_base_image "base-go" ;;
    esac

    if ! docker image inspect "$tag" &>/dev/null; then
        echo "Building project image: $tag ..."
        docker build -t "$tag" -f "$dockerfile" "$REPO_ROOT/docker"
    fi
}

# ── Volume & Worktree Management ─────────────────────────────────────────────

volume_name() {
    local project="$1"
    echo "${IMAGE_PREFIX}-${project}-src"
}

ensure_clone() {
    local project="$1" repo="$2" image="$3" vol="$4" submodules="$5"

    # Check if the volume already has a clone
    local has_git
    has_git=$(docker run --rm -v "${vol}:/workspace" "$image" \
        sh -c '[ -d /workspace/.git ] && echo yes || echo no') || has_git="error"

    if [ "$has_git" = "error" ]; then
        die "Failed to check volume $vol. Is the Docker daemon running?"
    fi

    if [ "$has_git" = "no" ]; then
        echo "Cloning $repo into volume $vol ..."
        local -a clone_cmd=(git clone --no-checkout)
        [ "$submodules" = "true" ] && clone_cmd+=(--recurse-submodules)
        # Pass repo as env var to avoid shell injection in bash -c strings
        docker run --rm \
            -v "${vol}:/workspace" \
            -e "CLONE_REPO=${repo}" \
            -e "CLONE_SUBMODULES=${submodules}" \
            "$image" \
            bash -c '
                git clone --no-checkout ${CLONE_SUBMODULES:+--recurse-submodules} "$CLONE_REPO" /tmp/_clone && \
                shopt -s dotglob && \
                mv /tmp/_clone/.git /workspace/.git && \
                rm -rf /tmp/_clone
            '
    else
        echo "Repository already cloned in volume $vol."
    fi
}

ensure_worktree() {
    local case_name="$1" commit="$2" image="$3" vol="$4" submodules="$5"
    local wt_path="/workspace/worktrees/${case_name}"

    local has_wt
    has_wt=$(docker run --rm -v "${vol}:/workspace" "$image" \
        sh -c '[ -d "$1" ] && echo yes || echo no' -- "$wt_path") || has_wt="error"

    if [ "$has_wt" = "error" ]; then
        die "Failed to check worktree for $case_name."
    fi

    if [ "$has_wt" = "no" ]; then
        echo "Creating worktree for $case_name at commit $commit ..."
        # Pass all values via env vars to avoid injection
        docker run --rm \
            -v "${vol}:/workspace" \
            -e "CASE_COMMIT=${commit}" \
            -e "CASE_WT_PATH=${wt_path}" \
            -e "CASE_SUBMODULES=${submodules}" \
            "$image" \
            bash -c '
                cd /workspace
                git fetch --all 2>/dev/null || true
                RESOLVED=$(git rev-parse "$CASE_COMMIT" 2>/dev/null || echo "$CASE_COMMIT")
                mkdir -p /workspace/worktrees
                git worktree add --detach "$CASE_WT_PATH" "$RESOLVED"
                if [ "$CASE_SUBMODULES" = "true" ]; then
                    cd "$CASE_WT_PATH"
                    git submodule update --init --recursive
                fi
            '
    else
        echo "Worktree already exists for $case_name."
    fi
}

# ── Docker Run Helpers ───────────────────────────────────────────────────────

# Populates the global RUN_ARGS array based on case.yaml.
# Caller uses: docker run "${RUN_ARGS[@]}" ...
build_run_args() {
    local yaml="$1"
    RUN_ARGS=()

    # Always add SYS_PTRACE for debugging
    RUN_ARGS+=("--cap-add=SYS_PTRACE")

    # Extra capabilities from case.yaml docker.caps
    local caps_line
    caps_line=$(yaml_nested "$yaml" "docker" "caps")
    local cleaned
    cleaned=$(echo "$caps_line" | tr -d '[]"' | tr ',' ' ')
    for cap in $cleaned; do
        cap=$(echo "$cap" | xargs)
        [ -n "$cap" ] && RUN_ARGS+=("--cap-add=$cap")
    done

    # Min CPUs
    local min_cpus
    min_cpus=$(yaml_nested "$yaml" "docker" "min_cpus")
    if [ -n "$min_cpus" ] && [ "$min_cpus" -gt 1 ] 2>/dev/null; then
        RUN_ARGS+=("--cpus=$min_cpus")
    fi
}

# ── Commands ─────────────────────────────────────────────────────────────────

cmd_setup() {
    local case_name="$1"
    local case_dir
    case_dir=$(find_case_dir "$case_name")
    local yaml
    yaml=$(find_case_yaml "$case_dir")

    local project repo commit submodules build_cmd
    project=$(yaml_val "$yaml" "project")
    repo=$(yaml_val "$yaml" "repo")
    commit=$(yaml_val "$yaml" "buggy_commit")
    submodules=$(yaml_val "$yaml" "submodules")
    build_cmd=$(yaml_nested "$yaml" "build" "command")

    local image="${IMAGE_PREFIX}/${project}"
    local vol
    vol=$(volume_name "$project")
    local wt_path="/workspace/worktrees/${case_name}"

    echo "=== bench.sh setup: $case_name ==="
    echo "  Project:  $project"
    echo "  Image:    $image"
    echo "  Volume:   $vol"
    echo "  Commit:   $commit"
    echo ""

    # Step 1: Build Docker image
    ensure_project_image "$project"

    # Step 2: Create volume and clone repo
    docker volume create "$vol" &>/dev/null
    ensure_clone "$project" "$repo" "$image" "$vol" "$submodules"

    # Step 3: Create worktree for this case
    ensure_worktree "$case_name" "$commit" "$image" "$vol" "$submodules"

    # Step 4: Build inside container
    if [ -n "$build_cmd" ]; then
        echo "Building $case_name ..."
        build_run_args "$yaml"

        # Pass build command via env var to avoid injection
        docker run --rm \
            "${RUN_ARGS[@]}" \
            -v "${vol}:/workspace" \
            -v "${case_dir}:/bench:ro" \
            -w "$wt_path" \
            -e "BUILD_CMD=${build_cmd}" \
            "$image" \
            bash -c 'eval "$BUILD_CMD"'
    fi

    echo ""
    echo "=== Setup complete: $case_name ==="
    echo "  Worktree: $wt_path (inside volume $vol)"
}

cmd_reproduce() {
    local case_name="$1"
    local case_dir
    case_dir=$(find_case_dir "$case_name")
    local yaml
    yaml=$(find_case_yaml "$case_dir")

    local project
    project=$(yaml_val "$yaml" "project")
    local image="${IMAGE_PREFIX}/${project}"
    local vol
    vol=$(volume_name "$project")
    local wt_path="/workspace/worktrees/${case_name}"

    echo "=== bench.sh reproduce: $case_name ==="

    build_run_args "$yaml"

    # Mount the full case directory at /bench so reproduce.sh can access
    # sibling files (configs, test scripts, etc.).
    # Set BENCH_WORKSPACE so WORK_DIR resolves to the worktree path:
    #   WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/<case-name>"
    #   → /workspace/worktrees/<case-name>
    docker run --rm \
        "${RUN_ARGS[@]}" \
        -v "${vol}:/workspace" \
        -v "${case_dir}:/bench:ro" \
        -w "$wt_path" \
        -e "BENCH_WORKSPACE=/workspace/worktrees" \
        "$image" \
        bash /bench/reproduce.sh
}

cmd_shell() {
    local case_name="$1"
    local case_dir
    case_dir=$(find_case_dir "$case_name")
    local yaml
    yaml=$(find_case_yaml "$case_dir")

    local project
    project=$(yaml_val "$yaml" "project")
    local image="${IMAGE_PREFIX}/${project}"
    local vol
    vol=$(volume_name "$project")
    local wt_path="/workspace/worktrees/${case_name}"

    echo "=== bench.sh shell: $case_name ==="
    echo "Dropping into interactive shell at $wt_path"
    echo "Type 'exit' to leave the container."
    echo ""

    build_run_args "$yaml"

    docker run --rm -it \
        "${RUN_ARGS[@]}" \
        -v "${vol}:/workspace" \
        -v "${case_dir}:/bench:ro" \
        -w "$wt_path" \
        -e "BENCH_WORKSPACE=/workspace/worktrees" \
        "$image" \
        bash
}

cmd_clean() {
    local case_name="$1"
    local case_dir
    case_dir=$(find_case_dir "$case_name")
    local yaml
    yaml=$(find_case_yaml "$case_dir")

    local project
    project=$(yaml_val "$yaml" "project")
    local vol
    vol=$(volume_name "$project")
    local wt_path="/workspace/worktrees/${case_name}"
    local image="${IMAGE_PREFIX}/${project}"

    # Verify volume exists
    if ! docker volume inspect "$vol" &>/dev/null; then
        echo "Volume $vol does not exist. Nothing to clean."
        return 0
    fi

    echo "Removing worktree for $case_name ..."
    docker run --rm \
        -v "${vol}:/workspace" \
        -e "CASE_WT_PATH=${wt_path}" \
        "$image" \
        bash -c 'cd /workspace && git worktree remove "$CASE_WT_PATH" --force 2>/dev/null || rm -rf "$CASE_WT_PATH"' 2>/dev/null || true

    echo "Cleaned $case_name."
}

cmd_clean_all() {
    echo "Removing all bug-bench containers, volumes, and images..."

    # Collect volume names first, then loop outside pipeline
    local -a vols
    mapfile -t vols < <(docker volume ls --format '{{.Name}}' | grep "^${IMAGE_PREFIX}-" || true)
    for v in "${vols[@]}"; do
        [ -z "$v" ] && continue
        echo "  Removing volume: $v"
        docker volume rm "$v" || echo "  WARNING: could not remove volume $v (in use?)"
    done

    # Collect image names first, then loop outside pipeline
    local -a imgs
    mapfile -t imgs < <(docker images --format '{{.Repository}}' | grep "^${IMAGE_PREFIX}/" | sort -u || true)
    for img in "${imgs[@]}"; do
        [ -z "$img" ] && continue
        echo "  Removing image: $img"
        docker rmi "$img" || echo "  WARNING: could not remove image $img (in use?)"
    done

    echo "Clean-all complete."
}

# ── Main ─────────────────────────────────────────────────────────────────────

usage() {
    cat <<EOF
Usage: bench.sh <command> [args]

Commands:
  setup <case-name>       Build Docker image, clone repo, checkout commit, build
  reproduce <case-name>   Run reproduce.sh inside container
  shell <case-name>       Interactive shell inside container
  clean <case-name>       Remove worktree for a case
  clean-all               Remove all bug-bench Docker artifacts

Environment:
  BENCH_WORKSPACE         Override workspace path (default: \$HOME/bug-bench)

Examples:
  ./bench.sh setup dragonfly-6856-flushslots-oob
  ./bench.sh reproduce dragonfly-6856-flushslots-oob
  ./bench.sh shell dragonfly-6856-flushslots-oob
EOF
}

require_cmd docker
docker info &>/dev/null || die "Docker daemon is not running or not accessible. Start it with: sudo systemctl start docker"

case "${1:-}" in
    setup)     [ -n "${2:-}" ] || die "Usage: bench.sh setup <case-name>"; cmd_setup "$2" ;;
    reproduce) [ -n "${2:-}" ] || die "Usage: bench.sh reproduce <case-name>"; cmd_reproduce "$2" ;;
    shell)     [ -n "${2:-}" ] || die "Usage: bench.sh shell <case-name>"; cmd_shell "$2" ;;
    clean)     [ -n "${2:-}" ] || die "Usage: bench.sh clean <case-name>"; cmd_clean "$2" ;;
    clean-all) cmd_clean_all ;;
    *)         usage; exit 1 ;;
esac
