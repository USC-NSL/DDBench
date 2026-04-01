#!/usr/bin/env bash
# bench.sh — Central orchestrator for bug-bench Docker-based isolation
# Usage:
#   bench.sh setup <case-name>                    Build image + clone + checkout + build
#   bench.sh reproduce <case-name>                Run reproduce.sh inside container
#   bench.sh shell <case-name> [--addon <name>]   Interactive shell (with optional addons)
#   bench.sh agent <case-name> --addon <name>     Launch an AI agent inside container
#   bench.sh reset <case-name>                    Revert to original buggy commit
#   bench.sh clean <case-name>                    Remove container + volumes for this case
#   bench.sh clean-all                            Remove all bug-bench containers + volumes + images
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
                git config --global --add safe.directory /workspace 2>/dev/null || true
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

# ── Addon Infrastructure ────────────────────────────────────────────────────
# Addons inject tools (AI agents, debuggers, profilers) into containers at
# runtime. See addons/README.md for the full contract.

TOOLS_VOL="${IMAGE_PREFIX}-tools"

# Container name for a case's interactive session (shell/agent).
container_name() {
    local case_name="$1"
    echo "${IMAGE_PREFIX}-${case_name}"
}

# Check if a named container is running.
container_running() {
    local name="$1"
    [ "$(docker inspect -f '{{.State.Running}}' "$name" 2>/dev/null)" = "true" ]
}

# Parse --addon flags from an argument list.
# Usage: parse_addons arg1 arg2 --addon claude-code --addon gdb-dashboard ...
# Sets:  ADDON_NAMES (array), AGENT_PROMPT (string), AGENT_CMD (string),
#         REMAINING_ARGS (array)
parse_addons() {
    ADDON_NAMES=()
    AGENT_PROMPT=""
    AGENT_CMD=""
    AGENT_CONFIG=""
    REMAINING_ARGS=()

    while [ $# -gt 0 ]; do
        case "$1" in
            --addon)
                [ -n "${2:-}" ] || die "--addon requires a name argument"
                ADDON_NAMES+=("$2")
                shift 2
                ;;
            --prompt)
                [ -n "${2:-}" ] || die "--prompt requires a value"
                AGENT_PROMPT="$2"
                shift 2
                ;;
            --cmd)
                [ -n "${2:-}" ] || die "--cmd requires a value"
                AGENT_CMD="$2"
                shift 2
                ;;
            --config)
                [ -n "${2:-}" ] || die "--config requires a path"
                AGENT_CONFIG="$2"
                shift 2
                ;;
            *)
                REMAINING_ARGS+=("$1")
                shift
                ;;
        esac
    done
}

# Resolve an addon name to its script path.
# Looks in addons/<name>.sh first (user override), then addons/examples/<name>.sh.
resolve_addon() {
    local name="$1"
    local user_script="$REPO_ROOT/addons/${name}.sh"
    local example_script="$REPO_ROOT/addons/examples/${name}.sh"

    if [ -f "$user_script" ]; then
        echo "$user_script"
    elif [ -f "$example_script" ]; then
        echo "$example_script"
    else
        die "Addon not found: $name (looked in addons/${name}.sh and addons/examples/${name}.sh)"
    fi
}

# Append addon-related Docker run args to the global RUN_ARGS array.
# Only adds mounts/env when addons are actually requested.
build_addon_args() {
    # Persistent tool cache
    docker volume create "$TOOLS_VOL" &>/dev/null
    RUN_ARGS+=("-v" "${TOOLS_VOL}:/opt/tools")

    # Mount addon scripts (read-only)
    RUN_ARGS+=("-v" "${REPO_ROOT}/addons:/addons:ro")

    # Tool directory env
    RUN_ARGS+=("-e" "ADDON_TOOL_DIR=/opt/tools")

    # Forward common API keys if set on host
    for key in ANTHROPIC_API_KEY OPENAI_API_KEY GEMINI_API_KEY MSWEA_MODEL_NAME MSWEA_MINI_CONFIG_PATH; do
        [ -n "${!key:-}" ] && RUN_ARGS+=("-e" "$key")
    done

    # Mount agent config directories if they exist on host
    if [ -d "$HOME/.claude" ]; then
        RUN_ARGS+=("-v" "${HOME}/.claude:/root/.claude:ro")
    fi
    if [ -d "$HOME/.aider" ]; then
        RUN_ARGS+=("-v" "${HOME}/.aider:/root/.aider:ro")
    fi
}

# Generate a bash snippet that installs addons and then exec's into a command.
# Usage: addon_entrypoint "bash" → returns a bash -c string
#
# The entrypoint:
#   1. Runs addon install scripts as root (they need apt-get, npm, etc.)
#   2. Creates a non-root user "bench" (agents like Claude Code refuse to run as root)
#   3. Sets up PATH, HOME, workspace ownership for the bench user
#   4. exec's the final command as the bench user
addon_entrypoint() {
    local final_cmd="$1"
    local setup_lines=""

    setup_lines+='export PATH="/opt/tools/bin:$PATH"'$'\n'

    # Run addon install scripts as root
    for name in "${ADDON_NAMES[@]}"; do
        local script_path
        script_path=$(resolve_addon "$name")
        local basename
        basename=$(basename "$script_path")
        # Addon scripts are mounted at /addons/ or /addons/examples/
        local container_path
        if [[ "$script_path" == *"/examples/"* ]]; then
            container_path="/addons/examples/$basename"
        else
            container_path="/addons/$basename"
        fi
        setup_lines+="bash \"$container_path\" || echo \"WARNING: addon $name failed\""$'\n'
    done

    # Create non-root user and switch to it (agents like Claude Code refuse root)
    setup_lines+='useradd -m -s /bin/bash bench 2>/dev/null || true'$'\n'
    setup_lines+='chown -R bench:bench /workspace/worktrees/"$CASE_NAME"'$'\n'
    setup_lines+='chmod -R a+rX /opt/tools 2>/dev/null || true'$'\n'
    # Copy agent configs to bench user home
    setup_lines+='for d in .claude .aider; do'$'\n'
    setup_lines+='  if [ -d "/root/$d" ]; then cp -a "/root/$d" "/home/bench/$d" 2>/dev/null; chown -R bench:bench "/home/bench/$d" 2>/dev/null; fi'$'\n'
    setup_lines+='done'$'\n'
    # Symlink workspace into bench home
    setup_lines+='mkdir -p /home/bench/bug-bench && ln -sfn /workspace/worktrees/"$CASE_NAME" /home/bench/bug-bench/"$CASE_NAME" 2>/dev/null || true'$'\n'
    setup_lines+='chown -R bench:bench /home/bench 2>/dev/null || true'$'\n'
    # Switch to bench user with correct env
    setup_lines+="exec runuser -u bench -- bash -c 'export PATH=\"/opt/tools/bin:\$PATH\" && export HOME=/home/bench && cd /workspace/worktrees/\"\$CASE_NAME\" && exec $final_cmd'"$'\n'

    echo "$setup_lines"
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

    # Step 5: Copy benchmark files into the worktree so agents can access
    # them from the workspace without needing access to /bench
    docker run --rm \
        -v "${vol}:/workspace" \
        -v "${case_dir}:/bench:ro" \
        -e "CASE_WT_PATH=${wt_path}" \
        -e "BUILD_CMD=${build_cmd}" \
        "$image" \
        bash -c '
            # Copy sanitized symptom
            [ -f /bench/symptom.md ] && cp /bench/symptom.md "$CASE_WT_PATH/SYMPTOM.md"
            # Create rebuild script — uses just the build step (not configure)
            if [ -n "$BUILD_CMD" ]; then
                REBUILD=""
                cd "$CASE_WT_PATH"
                # Detect build system and generate minimal incremental command
                if [ -d build-dbg ] && [ -f build-dbg/build.ninja ]; then
                    # Ninja build (Dragonfly)
                    TARGET=$(grep -oP "(?<=ninja )\S+" build-dbg/build.ninja 2>/dev/null || echo "")
                    [ -z "$TARGET" ] && TARGET=$(echo "$BUILD_CMD" | grep -oP "ninja\s+\K\S+" || echo "")
                    REBUILD="cd build-dbg && ninja ${TARGET:-}"
                elif [ -d build ] && [ -f build/build.ninja ]; then
                    # Ninja build (ClickHouse)
                    TARGET=$(echo "$BUILD_CMD" | grep -oP "ninja[^&]*" | grep -oP "(?<=ninja\s).*" || echo "")
                    REBUILD="cd build && ninja ${TARGET:-}"
                elif [ -f build/dev/build.ninja ]; then
                    # Ninja build (Seastar)
                    REBUILD="ninja -C build/dev"
                elif [ -d build ] && [ -f build/Makefile ]; then
                    # Make build (Kvrocks, RocksDB)
                    TARGET=$(echo "$BUILD_CMD" | grep -oP "make\s+.*?(?=\s*$)" | sed "s/make//" | xargs || echo "")
                    REBUILD="cd build && make -j\$(nproc) ${TARGET:-}"
                elif echo "$BUILD_CMD" | grep -q "go build"; then
                    # Go build (NATS)
                    REBUILD="$BUILD_CMD"
                elif echo "$BUILD_CMD" | grep -q "^make"; then
                    # Make at root (etcd)
                    REBUILD="$BUILD_CMD"
                else
                    # Fallback: full build command
                    REBUILD="$BUILD_CMD"
                fi
                cat > "$CASE_WT_PATH/REBUILD.sh" <<REBUILDEOF
#!/usr/bin/env bash
set -euo pipefail
echo "Rebuilding (incremental) ..."
cd "\$(dirname "\${BASH_SOURCE[0]}")"
$REBUILD
REBUILDEOF
                chmod +x "$CASE_WT_PATH/REBUILD.sh"
            fi
        '

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
    local build_cmd
    build_cmd=$(yaml_nested "$yaml" "build" "command")
    local cname
    cname="$(container_name "$case_name")"

    echo "=== bench.sh reproduce: $case_name ==="

    build_run_args "$yaml"

    # Rebuild before reproducing (incremental — only recompiles changed files)
    if [ -n "$build_cmd" ]; then
        echo "Rebuilding (incremental) ..."
        docker run --rm \
            "${RUN_ARGS[@]}" \
            -v "${vol}:/workspace" \
            -w "$wt_path" \
            -e "BUILD_CMD=${build_cmd}" \
            "$image" \
            bash -c 'eval "$BUILD_CMD"'
    fi

    # Kill any leftover container RIGHT BEFORE starting the named one
    # (not earlier — the rebuild step above can take minutes, during which
    # another process could recreate the container).
    docker rm -f "$cname" 2>/dev/null || true

    # Run reproduce.sh in a named container so external scripts can track/kill it
    # on timeout. The --rm flag still ensures cleanup on normal exit.
    docker run --rm --name "$cname" \
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
    shift
    parse_addons "$@"

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
    local cname
    cname=$(container_name "$case_name")

    # If container is already running, exec into it
    if container_running "$cname"; then
        echo "=== bench.sh shell: $case_name (attaching to running container) ==="

        # Install new addons if requested on a running container
        if [ ${#ADDON_NAMES[@]} -gt 0 ]; then
            echo "  Installing addons: ${ADDON_NAMES[*]}"
            for name in "${ADDON_NAMES[@]}"; do
                local script_path
                script_path=$(resolve_addon "$name")
                local bname
                bname=$(basename "$script_path")
                local cpath
                if [[ "$script_path" == *"/examples/"* ]]; then
                    cpath="/addons/examples/$bname"
                else
                    cpath="/addons/$bname"
                fi
                docker exec "$cname" bash -c "export PATH=/opt/tools/bin:\$PATH && bash \"$cpath\"" || echo "WARNING: addon $name failed"
            done
        fi

        echo "Type 'exit' to leave the shell (container keeps running)."
        echo ""
        docker exec -it -w "$wt_path" \
            -e "CASE_NAME=${case_name}" \
            "$cname" \
            bash -c 'export PATH="/opt/tools/bin:$PATH" && exec bash'
        return
    fi

    # Start a new persistent container
    echo "=== bench.sh shell: $case_name ==="
    [ ${#ADDON_NAMES[@]} -gt 0 ] && echo "  Addons: ${ADDON_NAMES[*]}"
    echo "Type 'exit' to leave the shell (container keeps running)."
    echo "Run './bench.sh stop $case_name' to stop the container."
    echo ""

    build_run_args "$yaml"

    if [ ${#ADDON_NAMES[@]} -gt 0 ]; then
        build_addon_args
    fi

    # Start container in background (persistent — no --rm)
    docker run -d \
        --name "$cname" \
        "${RUN_ARGS[@]}" \
        -v "${vol}:/workspace" \
        -v "${case_dir}:/bench:ro" \
        -w "$wt_path" \
        -e "BENCH_WORKSPACE=/workspace/worktrees" \
        -e "CASE_NAME=${case_name}" \
        "$image" \
        sleep infinity >/dev/null

    # Run addon setup inside the container (as root)
    if [ ${#ADDON_NAMES[@]} -gt 0 ]; then
        local entrypoint
        entrypoint=$(addon_entrypoint "true")
        docker exec "$cname" bash -c "$entrypoint"
    fi

    # Exec into the container
    docker exec -it -w "$wt_path" \
        -e "CASE_NAME=${case_name}" \
        "$cname" \
        bash -c 'export PATH="/opt/tools/bin:$PATH" && exec bash'
}

cmd_agent() {
    local case_name="$1"
    shift
    parse_addons "$@"

    [ ${#ADDON_NAMES[@]} -gt 0 ] || die "agent command requires at least one --addon flag"

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
    local cname
    cname=$(container_name "$case_name")

    # Determine the agent command
    local agent_cmd="${AGENT_CMD}"
    if [ -z "$agent_cmd" ]; then
        case "${ADDON_NAMES[0]}" in
            claude-code)    agent_cmd="claude" ;;
            aider)          agent_cmd="aider" ;;
            codex)          agent_cmd="codex" ;;
            mini-swe-agent) agent_cmd="mini" ;;
            *)              agent_cmd="bash" ;;
        esac
    fi

    local final_cmd="$agent_cmd"
    if [ -n "$AGENT_PROMPT" ]; then
        case "$agent_cmd" in
            claude) final_cmd="claude --print \"$AGENT_PROMPT\"" ;;
            aider)  final_cmd="aider --message \"$AGENT_PROMPT\"" ;;
            mini)
                local mini_args="-y --exit-immediately"
                [ -n "$AGENT_CONFIG" ] && mini_args="$mini_args --config /configs/agent_config.yaml"
                final_cmd="mini $mini_args -t \"$AGENT_PROMPT\""
                ;;
            *)      final_cmd="$agent_cmd" ;;
        esac
    fi

    echo "=== bench.sh agent: $case_name ==="
    echo "  Addons: ${ADDON_NAMES[*]}"
    [ -n "$AGENT_PROMPT" ] && echo "  Prompt: ${AGENT_PROMPT:0:80}..."
    echo ""

    # Reuse running container if available
    if container_running "$cname"; then
        echo "Attaching to running container ..."
        docker exec -it -w "$wt_path" \
            -e "CASE_NAME=${case_name}" \
            "$cname" \
            bash -c "export PATH=/opt/tools/bin:\$PATH && exec $final_cmd"
        return
    fi

    # Start a new persistent container
    build_run_args "$yaml"
    build_addon_args

    # Mount agent config file if provided
    if [ -n "$AGENT_CONFIG" ]; then
        local config_abs
        config_abs=$(cd "$(dirname "$AGENT_CONFIG")" && pwd)/$(basename "$AGENT_CONFIG")
        [ -f "$config_abs" ] || die "Config file not found: $AGENT_CONFIG"
        RUN_ARGS+=("-v" "${config_abs}:/configs/agent_config.yaml:ro")
    fi

    docker run -d \
        --name "$cname" \
        "${RUN_ARGS[@]}" \
        -v "${vol}:/workspace" \
        -v "${case_dir}:/bench:ro" \
        -w "$wt_path" \
        -e "BENCH_WORKSPACE=/workspace/worktrees" \
        -e "CASE_NAME=${case_name}" \
        "$image" \
        sleep infinity >/dev/null

    # Run addon setup inside the container (as root)
    local entrypoint
    entrypoint=$(addon_entrypoint "true")
    docker exec "$cname" bash -c "$entrypoint"

    # Launch agent
    docker exec -it -w "$wt_path" \
        -e "CASE_NAME=${case_name}" \
        "$cname" \
        bash -c "export PATH=/opt/tools/bin:\$PATH && exec $final_cmd"
}

cmd_stop() {
    local case_name="$1"
    local cname
    cname=$(container_name "$case_name")

    if container_running "$cname"; then
        echo "Stopping container $cname ..."
        docker stop "$cname" >/dev/null
        docker rm "$cname" >/dev/null 2>&1 || true
        echo "Stopped."
    elif docker inspect "$cname" &>/dev/null; then
        echo "Container $cname exists but is not running. Removing ..."
        docker rm "$cname" >/dev/null 2>&1 || true
        echo "Removed."
    else
        echo "No running container for $case_name."
    fi
}

cmd_reset() {
    local case_name="$1"
    local case_dir
    case_dir=$(find_case_dir "$case_name")
    local yaml
    yaml=$(find_case_yaml "$case_dir")

    local project submodules commit
    project=$(yaml_val "$yaml" "project")
    submodules=$(yaml_val "$yaml" "submodules")
    commit=$(yaml_val "$yaml" "buggy_commit")
    local image="${IMAGE_PREFIX}/${project}"
    local vol
    vol=$(volume_name "$project")
    local wt_path="/workspace/worktrees/${case_name}"

    echo "=== bench.sh reset: $case_name ==="
    echo "Reverting to the original buggy commit ($commit)..."

    docker run --rm \
        -v "${vol}:/workspace" \
        -e "CASE_WT_PATH=${wt_path}" \
        -e "CASE_COMMIT=${commit}" \
        -e "CASE_SUBMODULES=${submodules}" \
        "$image" \
        bash -c '
            cd "$CASE_WT_PATH" || exit 1
            git config --global --add safe.directory /workspace 2>/dev/null || true

            # Preserve benchmark files across reset
            [ -f SYMPTOM.md ] && cp SYMPTOM.md /tmp/_symptom_backup.md
            [ -f REBUILD.sh ] && cp REBUILD.sh /tmp/_rebuild_backup.sh

            # Step 1: Clean working tree (discard all modifications)
            git checkout -- .
            git clean -fd

            # Step 2: Move HEAD back to the buggy commit
            RESOLVED=$(git rev-parse "$CASE_COMMIT" 2>/dev/null || echo "$CASE_COMMIT")
            CURRENT=$(git rev-parse HEAD)
            if [ "$CURRENT" != "$RESOLVED" ]; then
                echo "HEAD was at $(git rev-parse --short HEAD), checking out $CASE_COMMIT ..."
                git checkout "$RESOLVED" 2>&1 | tail -1
            fi

            # Step 3: Restore benchmark files
            [ -f /tmp/_symptom_backup.md ] && mv /tmp/_symptom_backup.md SYMPTOM.md
            [ -f /tmp/_rebuild_backup.sh ] && mv /tmp/_rebuild_backup.sh REBUILD.sh

            # Step 4: Reset submodules if applicable
            if [ "$CASE_SUBMODULES" = "true" ]; then
                git submodule update --init --recursive 2>&1 | tail -1
                git submodule foreach --recursive git checkout -- .
                git submodule foreach --recursive git clean -fd
            fi
        '

    echo "Reset complete. Source is back to the original buggy state."
    echo "Run './bench.sh reproduce $case_name' to verify the bug is still present."
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

    # Stop and remove any containers that use this volume (includes VS Code devcontainers)
    local -a using
    mapfile -t using < <(docker ps -aq --filter "volume=${vol}" 2>/dev/null || true)
    for cid in "${using[@]}"; do
        [ -z "$cid" ] && continue
        echo "Stopping container $cid ..."
        docker stop "$cid" 2>/dev/null || true
        docker rm "$cid" 2>/dev/null || true
    done

    echo "Removing worktree for $case_name ..."
    docker run --rm \
        -v "${vol}:/workspace" \
        -e "CASE_WT_PATH=${wt_path}" \
        "$image" \
        bash -c 'git config --global --add safe.directory /workspace 2>/dev/null; cd /workspace && git worktree remove "$CASE_WT_PATH" --force 2>/dev/null || rm -rf "$CASE_WT_PATH"' 2>/dev/null || true

    echo "Cleaned $case_name."
}

cmd_clean_all() {
    echo "Removing all bug-bench containers, volumes, and images..."

    # Find all bug-bench volumes, then stop any container using them
    local -a vols
    mapfile -t vols < <(docker volume ls --format '{{.Name}}' | grep "^${IMAGE_PREFIX}-" || true)
    for v in "${vols[@]}"; do
        [ -z "$v" ] && continue
        local -a using
        mapfile -t using < <(docker ps -aq --filter "volume=${v}" 2>/dev/null || true)
        for cid in "${using[@]}"; do
            [ -z "$cid" ] && continue
            echo "  Stopping container $cid (uses volume $v) ..."
            docker stop "$cid" 2>/dev/null || true
            docker rm "$cid" 2>/dev/null || true
        done
    done
    for v in "${vols[@]}"; do
        [ -z "$v" ] && continue
        echo "  Removing volume: $v"
        docker volume rm "$v" || echo "  WARNING: could not remove volume $v (in use?)"
    done

    # Remove addon tool cache volume
    if docker volume inspect "$TOOLS_VOL" &>/dev/null; then
        echo "  Removing addon tool cache: $TOOLS_VOL"
        docker volume rm "$TOOLS_VOL" || echo "  WARNING: could not remove volume $TOOLS_VOL (in use?)"
    fi

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
  setup <case-name>                    Build Docker image, clone repo, checkout commit, build
  reproduce <case-name>                Run reproduce.sh inside container
  shell <case-name> [--addon <name>]   Interactive shell (reuses running container)
  agent <case-name> --addon <name>     Launch an AI agent inside container
  stop <case-name>                     Stop the running container for a case
  reset <case-name>                    Revert source to original buggy commit (undo all edits)
  clean <case-name>                    Remove worktree + container for a case
  clean-all                            Remove all bug-bench Docker artifacts

Addon Options (for shell and agent):
  --addon <name>       Install a tool addon (repeatable). See addons/README.md
  --prompt <text>      Pass a prompt to the agent (agent command only)
  --cmd <command>      Override the agent command to run (agent command only)
  --config <path>      Agent config file (mounted into container, agent command only)

Environment:
  BENCH_WORKSPACE         Override workspace path (default: \$HOME/bug-bench)
  ANTHROPIC_API_KEY       Forwarded to container for Claude Code
  OPENAI_API_KEY          Forwarded to container for Codex/Aider
  MSWEA_MODEL_NAME        Forwarded to container for mini-swe-agent (required, no default)

Examples:
  ./bench.sh setup dragonfly-6856-flushslots-oob
  ./bench.sh reproduce dragonfly-6856-flushslots-oob
  ./bench.sh shell dragonfly-6856-flushslots-oob
  ./bench.sh shell dragonfly-6856-flushslots-oob --addon claude-code --addon custom-gdb-dashboard
  ./bench.sh agent dragonfly-6856-flushslots-oob --addon claude-code
  ./bench.sh agent dragonfly-6856-flushslots-oob --addon aider --prompt "Fix the bug in SYMPTOM.md"
  ./bench.sh agent dragonfly-6856-flushslots-oob --addon mini-swe-agent --prompt "Fix the bug"
EOF
}

require_cmd docker
docker info &>/dev/null || die "Docker daemon is not running or not accessible. Start it with: sudo systemctl start docker"

case "${1:-}" in
    setup)     [ -n "${2:-}" ] || die "Usage: bench.sh setup <case-name>"; cmd_setup "$2" ;;
    reproduce) [ -n "${2:-}" ] || die "Usage: bench.sh reproduce <case-name>"; cmd_reproduce "$2" ;;
    shell)     [ -n "${2:-}" ] || die "Usage: bench.sh shell <case-name> [--addon <name>]"; shift; cmd_shell "$@" ;;
    agent)     [ -n "${2:-}" ] || die "Usage: bench.sh agent <case-name> --addon <name>"; shift; cmd_agent "$@" ;;
    stop)      [ -n "${2:-}" ] || die "Usage: bench.sh stop <case-name>"; cmd_stop "$2" ;;
    reset)     [ -n "${2:-}" ] || die "Usage: bench.sh reset <case-name>"; cmd_reset "$2" ;;
    clean)     [ -n "${2:-}" ] || die "Usage: bench.sh clean <case-name>"; cmd_clean "$2" ;;
    clean-all) cmd_clean_all ;;
    *)         usage; exit 1 ;;
esac
