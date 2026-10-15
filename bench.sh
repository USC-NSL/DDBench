#!/usr/bin/env bash
# bench.sh -- DDBench orchestrator: builds, runs and scores bug cases in Docker.
#
# Run `./bench.sh help` for the full command list. Every command that acts on a
# case takes the case name (a directory under cases/).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$REPO_ROOT/bench.sh"
IMAGE_PREFIX="bug-bench"

# ── Opaque case identity ────────────────────────────────────────────────────
#
# An agent must not be able to tell which upstream issue it is working on: the
# case name carries the issue number and a diagnostic slug. Nothing an agent
# container can observe may contain it -- not the working directory, the
# environment, the hostname, mount sources in /proc/self/mountinfo (which list
# Docker volume names and bind-mount host paths), or files in the worktree.
#
#   * Every container (setup, reproduce, shell, agent, devcontainer) uses the
#     same worktree path, WT_PATH. Absolute paths baked into build artifacts
#     (CMakeCache.txt, compile_commands.json, Go/Rust/Java build outputs) are
#     therefore identical everywhere and carry no case information.
#   * Docker objects (worktree, context and dependency volumes, container) are
#     named after case_uid(), a hash of the case name.
#   * context/ and the agent's --output-dir are staged under opaque names
#     instead of being bind-mounted from paths that contain the case name.
#
# bench.sh commands keep taking the case name; only Docker sees the uid.
WT_PATH="/workspace/src"

# Per-case dependency caches (Go modules + build cache, Cargo, Gradle, Maven).
# See "Dependency caches" below.
DEPS_PATH="/deps"

# Host-side state: agent output staging, locks, eval logs (gitignored).
STATE_DIR="$REPO_ROOT/.bench"

# Default wall-clock limit for one oracle run under eval / validate-oracle.
DEFAULT_RUN_TIMEOUT=3600

# Global array populated by build_run_args, consumed by Docker commands.
RUN_ARGS=()

# Global array of -e flags for API keys, populated by build_addon_args,
# used by both docker run (via RUN_ARGS) and docker exec calls.
API_KEY_ENV_ARGS=()

# ── Helpers ──────────────────────────────────────────────────────────────────

# Exit code for die(). `reproduce` sets it to 2 so that infrastructure problems
# are reported as ERROR (2), never confused with FAIL (1). See cmd_reproduce.
DIE_CODE=1
die() { echo "ERROR: $*" >&2; exit "$DIE_CODE"; }
warn() { echo "WARNING: $*" >&2; }

sha256_hex() {
    if command -v sha256sum &>/dev/null; then sha256sum | cut -d' ' -f1
    else shasum -a 256 | cut -d' ' -f1; fi
}

# Opaque, stable identifier for a case (see "Opaque case identity" above).
case_uid() {
    printf '%s' "$1" | sha256_hex | cut -c1-12
}

require_cmd() {
    command -v "$1" &>/dev/null || die "$1 is required but not found. Please install it."
}

now_utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# JSON string literal for an arbitrary string. Invalid UTF-8 and control
# characters (other than tab/newline/CR) are dropped so the result is always
# valid JSON. Without iconv, everything outside printable ASCII is dropped.
json_str() {
    local s
    if command -v iconv &>/dev/null; then
        s=$(printf '%s' "$1" | iconv -c -f UTF-8 -t UTF-8 2>/dev/null | LC_ALL=C tr -d '\000-\010\013\014\016-\037\177')
    else
        s=$(printf '%s' "$1" | LC_ALL=C tr -cd '\11\12\15\40-\176')
    fi
    s=${s//\\/\\\\}; s=${s//\"/\\\"}
    s=${s//$'\n'/\\n}; s=${s//$'\r'/\\r}; s=${s//$'\t'/\\t}
    printf '"%s"' "$s"
}

# Host-wide advisory locks (mkdir is atomic). Used around image builds and the
# per-project clone so that parallel setups of the same project don't race.
# A lock whose holder has exited is reclaimed.
lock_acquire() {
    local dir="$STATE_DIR/locks/$1.lock" pid announced=false
    mkdir -p "$STATE_DIR/locks"
    while ! mkdir "$dir" 2>/dev/null; do
        pid=$(cat "$dir/pid" 2>/dev/null || true)
        if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null && [ ! -d "/proc/$pid" ]; then
            rm -rf "$dir"; continue
        fi
        $announced || echo "Waiting for lock '$1' (held by pid ${pid:-?}) ..." >&2
        announced=true
        sleep 2
    done
    echo $$ >"$dir/pid"
}
lock_release() { rm -rf "$STATE_DIR/locks/$1.lock"; }

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
    val=$(echo "$line" | sed "s/^${key}:[[:space:]]*//" | sed 's/[[:space:]]#.*$//' \
          | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/")
    [ "$val" = "null" ] && val=""
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
    case "$case_name" in */*|.*|"") die "Invalid case name: '$case_name'" ;; esac
    local case_dir="$REPO_ROOT/cases/$case_name"
    [ -d "$case_dir" ] || die "Case directory not found: $case_dir (see ./bench.sh list)"
    echo "$case_dir"
}

find_case_yaml() {
    local case_dir="$1"
    local yaml="$case_dir/case.yaml"
    [ -f "$yaml" ] || die "case.yaml not found in $case_dir"
    echo "$yaml"
}

# ── CPU and network policy ───────────────────────────────────────────────────

DOCKER_NCPU=""        # CPUs available to the Docker daemon (set in main)
CPU_WARNED=false

# Effective --cpus for a case: min(case docker.num_cpus, Docker host CPUs),
# further capped by BENCH_CPUS. BENCH_CPUS never raises a case above its
# num_cpus: some oracles depend on it (dragonfly-6687 sizes its thread pool from
# the CPU quota). Sets EFFECTIVE_CPUS (empty = no limit).
resolve_cpus() {
    local yaml="$1" want host eff
    want=$(yaml_nested "$yaml" "docker" "num_cpus")
    [[ "$want" =~ ^[0-9]+$ ]] && [ "$want" -ge 1 ] || want=""
    host="${DOCKER_NCPU:-}"
    [[ "$host" =~ ^[0-9]+$ ]] && [ "$host" -ge 1 ] || host=$(nproc 2>/dev/null || echo 1)
    eff="$want"
    if [ -n "${BENCH_CPUS:-}" ]; then
        [[ "$BENCH_CPUS" =~ ^[0-9]+$ ]] && [ "$BENCH_CPUS" -ge 1 ] || die "BENCH_CPUS must be a positive integer"
        if [ -z "$eff" ] || [ "$BENCH_CPUS" -lt "$eff" ]; then eff="$BENCH_CPUS"; fi
    fi
    if [ -n "$eff" ] && [ "$eff" -gt "$host" ]; then eff="$host"; fi
    if [ -n "$want" ] && [ -n "$eff" ] && [ "$eff" -lt "$want" ] && [ "$CPU_WARNED" = false ]; then
        warn "using $eff CPU(s) instead of the case's num_cpus=$want (Docker host has $host;" \
             "BENCH_CPUS=${BENCH_CPUS:-unset}). Timing-sensitive oracles may behave differently."
        CPU_WARNED=true
    fi
    EFFECTIVE_CPUS="$eff"
}

# Scoring (reproduce/rebuild/reset builds) runs with --network none unless the
# case opts out with docker.offline: false, or BENCH_OFFLINE=0 is set.
case_offline() {
    local yaml="$1" v
    [ "${BENCH_OFFLINE:-1}" = "0" ] && return 1
    v=$(yaml_nested "$yaml" "docker" "offline")
    [ "$v" = "false" ] && return 1
    return 0
}

# Sets NET_ARGS for a container. "offline" = loopback only; the hostname is
# mapped to 127.0.0.1 because Java/Erlang test harnesses resolve it.
network_args() {
    NET_ARGS=()
    if [ "$1" = "offline" ]; then
        NET_ARGS=(--network none --hostname ddbench --add-host ddbench:127.0.0.1)
    fi
}

# ── Image Management ─────────────────────────────────────────────────────────
#
# Images are rebuilt automatically when their Dockerfile (or a bug-bench base
# image's Dockerfile) changes: each image carries the sha256 of those files in
# the label ddbench.fingerprint.

dockerfile_path() { echo "$REPO_ROOT/docker/$1.Dockerfile"; }

# bug-bench images a Dockerfile builds on (FROM or COPY --from=).
image_deps() {
    sed -nE "s#^[[:space:]]*(FROM|COPY[[:space:]]+--from=)[[:space:]]*${IMAGE_PREFIX}/([A-Za-z0-9._-]+).*#\2#p" \
        "$(dockerfile_path "$1")" | sort -u
}

image_fingerprint() {
    local name="$1" dep
    {
        cat "$(dockerfile_path "$name")"
        for dep in $(image_deps "$name"); do image_fingerprint "$dep"; done
    } | sha256_hex
}

image_label() {
    local v
    v=$(docker image inspect -f "{{index .Config.Labels \"$2\"}}" "$1" 2>/dev/null) || return 0
    [ "$v" = "<no value>" ] || echo "$v"
}

ensure_image() {
    local name="$1" tag="${IMAGE_PREFIX}/$1" dockerfile fp dep
    dockerfile=$(dockerfile_path "$name")
    [ -f "$dockerfile" ] || die "Dockerfile not found: $dockerfile"
    for dep in $(image_deps "$name"); do ensure_image "$dep"; done
    fp=$(image_fingerprint "$name")
    [ "$(image_label "$tag" ddbench.fingerprint)" = "$fp" ] && return 0
    lock_acquire "image-$name"
    if [ "$(image_label "$tag" ddbench.fingerprint)" != "$fp" ]; then
        if docker image inspect "$tag" &>/dev/null; then
            echo "Rebuilding image $tag (its Dockerfile changed) ..."
        else
            echo "Building image $tag ..."
        fi
        if ! docker build --label "ddbench.fingerprint=$fp" -t "$tag" -f "$dockerfile" "$REPO_ROOT/docker"; then
            lock_release "image-$name"
            die "docker build failed for $tag"
        fi
    fi
    lock_release "image-$name"
}

ensure_project_image() { ensure_image "$1"; }

# ── Volume & Case-Repo Management ────────────────────────────────────────────
#
# CONTAINMENT: an agent must never be able to read commits that come AFTER the
# buggy commit. Those commits contain the upstream fix. Two properties enforce
# containment:
#
#   1. Each case gets its OWN source volume. A sibling case of the same project
#      may sit at a later commit whose ancestry contains THIS case's fix, so
#      cases must not share a filesystem.
#   2. Each case repository is built by fetching ONLY the ancestry of the buggy
#      commit from a per-project cache. Descendant objects are never transferred,
#      so `git show <fix-sha>`, `git log --all` and `git diff HEAD..main` have
#      nothing to find — the objects are absent, not merely unreachable.
#
# The full clone lives in a separate cache volume that is mounted ONLY during
# setup (and read-only by reset to resolve the buggy commit), never into agent
# or reproduce containers.

volume_name() {
    echo "${IMAGE_PREFIX}-ws-$(case_uid "$1")"
}

# Read-only copy of cases/<case>/context/, mounted only with --context.
context_volume_name() {
    echo "${IMAGE_PREFIX}-ctx-$(case_uid "$1")"
}

# Per-case dependency cache, mounted at $DEPS_PATH (see "Dependency caches").
deps_volume_name() {
    echo "${IMAGE_PREFIX}-deps-$(case_uid "$1")"
}

# Volume name used before the opaque layout (worktree at
# /workspace/worktrees/<case>). Only used to detect stale setups.
legacy_volume_name() {
    echo "${IMAGE_PREFIX}-case-$1-src"
}

# Fail unless the case has a worktree volume in the current layout.
require_case_volume() {
    local case_name="$1" vol legacy
    vol=$(volume_name "$case_name")
    legacy=$(legacy_volume_name "$case_name")
    docker volume inspect "$vol" &>/dev/null && return 0
    if docker volume inspect "$legacy" &>/dev/null; then
        die "$case_name was set up by an older bench.sh (volume $legacy, worktree under
  /workspace/worktrees/$case_name). That layout exposes the case name inside agent
  containers and is no longer used. Re-run:
      ./bench.sh setup $case_name
  Old volumes can be listed with: ./bench.sh legacy-volumes"
    fi
    die "$case_name is not set up (no volume $vol). Run: ./bench.sh setup $case_name"
}

cache_volume_name() {
    local project="$1"
    echo "${IMAGE_PREFIX}-${project}-cache"
}

# Path of the full-history cache inside the cache volume.
CACHE_GIT_DIR="/cache/repo.git"

ensure_clone() {
    local project="$1" repo="$2" image="$3" cache_vol="$4"

    # Check if the cache volume already has a clone
    local has_git
    has_git=$(docker run --rm -v "${cache_vol}:/cache" -e "CACHE_GIT_DIR=${CACHE_GIT_DIR}" "$image" \
        sh -c '[ -d "$CACHE_GIT_DIR" ] && echo yes || echo no') || has_git="error"

    if [ "$has_git" = "error" ]; then
        die "Failed to check cache volume $cache_vol. Is the Docker daemon running?"
    fi

    if [ "$has_git" = "no" ]; then
        echo "Cloning $repo into cache volume $cache_vol ..."
        # Pass repo as env var to avoid shell injection in bash -c strings.
        # The cache is bare: it is only ever used as a fetch source.
        docker run --rm \
            -v "${cache_vol}:/cache" \
            -e "CLONE_REPO=${repo}" \
            -e "CACHE_GIT_DIR=${CACHE_GIT_DIR}" \
            "$image" \
            bash -c '
                set -e
                rm -rf "$CACHE_GIT_DIR.partial"
                git clone --quiet --bare "$CLONE_REPO" "$CACHE_GIT_DIR.partial"
                # Let per-case repos fetch the buggy commit by SHA directly.
                git --git-dir="$CACHE_GIT_DIR.partial" config uploadpack.allowAnySHA1InWant true
                mv "$CACHE_GIT_DIR.partial" "$CACHE_GIT_DIR"
            '
    else
        echo "Repository already cached in volume $cache_vol."
    fi
}

case_repo_exists() {
    local vol="$1" image="$2" r
    r=$(docker run --rm -v "${vol}:/workspace" "$image" \
        sh -c '[ -e "$1/.git" ] && echo yes || echo no' -- "$WT_PATH") || r="error"
    echo "$r"
}

# Create the per-case repository, truncated to the buggy commit's ancestry.
ensure_case_repo() {
    local case_name="$1" commit="$2" image="$3" vol="$4" cache_vol="$5" submodules="$6" repo="$7"
    local wt_path="$WT_PATH"

    local has_wt
    has_wt=$(case_repo_exists "$vol" "$image")

    if [ "$has_wt" = "error" ]; then
        die "Failed to check case repository for $case_name."
    fi

    if [ "$has_wt" = "yes" ]; then
        echo "Case repository already exists for $case_name."
        return 0
    fi

    echo "Creating truncated case repository for $case_name at commit $commit ..."
    # Cache is mounted read-only: setup can read history, but nothing here can
    # write it back, and it is never mounted for agent runs.
    docker run --rm \
        -v "${vol}:/workspace" \
        -v "${cache_vol}:/cache:ro" \
        -e "CASE_COMMIT=${commit}" \
        -e "CASE_WT_PATH=${wt_path}" \
        -e "CASE_SUBMODULES=${submodules}" \
        -e "CASE_REPO=${repo}" \
        -e "CACHE_GIT_DIR=${CACHE_GIT_DIR}" \
        "$image" \
        bash -c '
            set -eu
            git config --global --add safe.directory "*" 2>/dev/null || true

            RESOLVED=$(git --git-dir="$CACHE_GIT_DIR" rev-parse --verify "${CASE_COMMIT}^{commit}")

            rm -rf "$CASE_WT_PATH"
            mkdir -p "$(dirname "$CASE_WT_PATH")"
            git init -q "$CASE_WT_PATH"
            cd "$CASE_WT_PATH"
            git config advice.detachedHead false

            # Transfer ONLY the ancestry of the buggy commit. Descendant objects
            # (which carry the upstream fix) are never sent over the wire.
            git fetch -q --no-tags --no-recurse-submodules "$CACHE_GIT_DIR" "$RESOLVED"
            git checkout -q --detach "$RESOLVED"

            if [ "$CASE_SUBMODULES" = "true" ]; then
                # .gitmodules may use URLs relative to the superproject remote,
                # so origin has to exist while submodules are resolved. It is
                # removed again immediately afterwards.
                git remote add origin "$CASE_REPO"
                git submodule update --init --recursive --quiet
                git remote remove origin
            fi

            # Strip every entry point to anything outside the checked-out
            # ancestry, then physically drop unreachable objects. Detached HEAD
            # keeps the ancestry itself alive.
            git for-each-ref --format="%(refname)" | while read -r ref; do
                git update-ref -d "$ref"
            done
            for r in $(git remote); do git remote remove "$r"; done
            rm -f "$(git rev-parse --git-dir)/FETCH_HEAD"
            git reflog expire --expire=now --all
            git gc --quiet --prune=now

            if [ "$CASE_SUBMODULES" = "true" ]; then
                git submodule foreach --recursive --quiet '\''
                    git for-each-ref --format="%(refname)" | while read -r ref; do
                        git update-ref -d "$ref"
                    done
                    for r in $(git remote); do git remote remove "$r"; done
                    git reflog expire --expire=now --all
                    git gc --quiet --prune=now
                '\''
            fi

            # Containment gate. If either assertion fires, the case repo can
            # expose post-buggy-commit history and MUST NOT be used for an
            # evaluation run. Fail setup loudly rather than score a tainted case.
            remaining_refs=$(git for-each-ref | wc -l)
            if [ "$remaining_refs" -ne 0 ]; then
                echo "CONTAINMENT FAILURE: $remaining_refs ref(s) survived truncation" >&2
                exit 1
            fi
            ancestry=$(git rev-list HEAD --count)
            in_store=$(git cat-file --batch-all-objects --batch-check="%(objecttype)" | grep -c "^commit$")
            if [ "$ancestry" != "$in_store" ]; then
                echo "CONTAINMENT FAILURE: $in_store commit objects present but ancestry is $ancestry" >&2
                exit 1
            fi
            echo "  containment OK: $ancestry commits, 0 refs, no remotes"
        '
}

# ── Dependency caches ────────────────────────────────────────────────────────
#
# Package managers download third-party dependencies (Go modules and toolchains,
# Cargo crates, Gradle and Maven artifacts) and keep build caches (GOCACHE).
# All of them are pointed at $DEPS_PATH, which is backed by a PER-CASE volume
# (deps_volume_name):
#
#   * setup populates it: the build runs online, then the oracle runs once
#     online ("warm-up") so test-only dependencies are fetched too. The stamp
#     $DEPS_PATH/.ddbench-warm records that this happened.
#   * reproduce / rebuild / reset mount it read-write and run OFFLINE
#     (--network none, GOPROXY=off, CARGO_NET_OFFLINE, Gradle/Maven offline).
#   * bench.sh shell (human sessions) mounts it read-write, online.
#   * bench.sh agent NEVER mounts it. Agent containers get the same environment
#     variables pointing at an empty, container-local $DEPS_PATH and download
#     what they need over their own network.
#
# Threat model: the cache is written by scoring runs, so it can hold artifacts
# compiled from oracle tests and from gold/candidate patches (GOCACHE, Gradle
# caches, Maven-installed project jars). It must therefore never be visible to
# an agent, and it is per case so that nothing (not even third-party content
# fetched for a later upstream version) crosses from one case to another. The
# third-party content it holds is pinned by the buggy commit's lock files
# (go.sum, Cargo.lock, Gradle/Maven coordinates).

DEPS_STAMP="$DEPS_PATH/.ddbench-warm"

# Sets DEPS_ENV: -e flags that point every package manager at $DEPS_PATH.
deps_env_args() {
    DEPS_ENV=(
        -e "GOMODCACHE=$DEPS_PATH/go/mod"
        -e "GOCACHE=$DEPS_PATH/go/build"
        -e "CARGO_HOME=$DEPS_PATH/cargo"
        -e "GRADLE_USER_HOME=$DEPS_PATH/gradle"
        -e "MAVEN_OPTS=-Dmaven.repo.local=$DEPS_PATH/m2"
    )
    if [ "$1" = "offline" ]; then
        DEPS_ENV+=(-e "DDBENCH_OFFLINE=1" -e "GOPROXY=off" -e "CARGO_NET_OFFLINE=true")
    fi
}

# Shell prologue for containers that build or run the oracle. Maven has no
# environment switch for offline mode, so a user settings file is written into
# the (ephemeral) container when DDBENCH_OFFLINE=1. Gradle is switched by the
# init script that prepare_deps_volume installs.
# shellcheck disable=SC2016  # expanded inside the container
CONTAINER_PROLOGUE='git config --global --add safe.directory "*" 2>/dev/null || true
if [ "${DDBENCH_OFFLINE:-}" = 1 ]; then
    mkdir -p "$HOME/.m2" && printf "<settings><offline>true</offline></settings>\n" >"$HOME/.m2/settings.xml"
fi
'

prepare_deps_volume() {
    local deps_vol="$1" image="$2"
    docker run --rm --network none -v "${deps_vol}:${DEPS_PATH}" -e "D=${DEPS_PATH}" "$image" bash -c '
        set -e
        mkdir -p "$D/go" "$D/cargo" "$D/gradle/init.d" "$D/m2"
        cat >"$D/gradle/init.d/ddbench-offline.gradle" <<EOF
// Installed by bench.sh: scoring containers run without network access.
if (System.getenv("DDBENCH_OFFLINE") == "1") {
    gradle.startParameter.offline = true
}
EOF
    ' || die "could not initialise dependency volume $deps_vol"
}

deps_warm() {
    local deps_vol="$1" image="$2"
    docker volume inspect "$deps_vol" &>/dev/null || return 1
    docker run --rm --network none -v "${deps_vol}:${DEPS_PATH}:ro" "$image" test -f "$DEPS_STAMP" 2>/dev/null
}

mark_deps_warm() {
    local deps_vol="$1" image="$2" note="$3"
    docker run --rm --network none -v "${deps_vol}:${DEPS_PATH}" -e "S=${DEPS_STAMP}" -e "N=${note}" "$image" \
        sh -c 'printf "%s\n" "$N" >"$S"' || die "could not write $DEPS_STAMP"
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

    # CPU limit. OMP_NUM_THREADS makes `nproc` (and so `make -j$(nproc)`)
    # report the same number instead of every host CPU.
    resolve_cpus "$yaml"
    if [ -n "$EFFECTIVE_CPUS" ]; then
        RUN_ARGS+=("--cpus=$EFFECTIVE_CPUS" "-e" "OMP_NUM_THREADS=$EFFECTIVE_CPUS")
    fi

    # Disable seccomp filtering (needed for io_uring syscalls)
    local seccomp_unconfined
    seccomp_unconfined=$(yaml_nested "$yaml" "docker" "seccomp_unconfined")
    if [ "$seccomp_unconfined" = "true" ]; then
        RUN_ARGS+=("--security-opt" "seccomp=unconfined")
    fi
}

# ── Addon Infrastructure ────────────────────────────────────────────────────
# Addons inject tools (AI agents, debuggers, profilers) into containers at
# runtime. See addons/README.md for the full contract.

TOOLS_VOL="${IMAGE_PREFIX}-tools"

# Container name for a case's interactive session (shell/agent) and for the
# reproduce run. Opaque; `docker ps --filter label=ddbench.case=<case>` finds it.
container_name() {
    echo "${IMAGE_PREFIX}-$(case_uid "$1")"
}

# Docker label for humans and tooling. Labels are only visible through the
# Docker API, never from inside the container.
case_label_args() {
    echo "--label=ddbench.case=$1"
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
    AGENT_OUTPUT_DIR=""
    AGENT_CONTEXT=false
    AGENT_FORCE=false
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
            --output-dir)
                [ -n "${2:-}" ] || die "--output-dir requires a path"
                AGENT_OUTPUT_DIR="$2"
                shift 2
                ;;
            --context)
                AGENT_CONTEXT=true
                shift
                ;;
            --force)
                AGENT_FORCE=true
                shift
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

    # Forward common API keys if set on host.
    # Build API_KEY_ENV_ARGS so docker exec calls can reuse them (docker exec
    # does NOT inherit env vars set via docker run -e).
    API_KEY_ENV_ARGS=()
    for key in \
        ANTHROPIC_AUTH_TOKEN ANTHROPIC_API_KEY ANTHROPIC_BASE_URL OPENAI_API_KEY GEMINI_API_KEY \
        DEEPSEEK_API_KEY TOGETHER_API_KEY FIREWORKS_API_KEY OPENROUTER_API_KEY \
        MSWEA_MODEL_NAME MSWEA_MINI_CONFIG_PATH MSWEA_CONFIGURED; do
        [ -n "${!key:-}" ] && API_KEY_ENV_ARGS+=("-e" "${key}=${!key}")
    done
    RUN_ARGS+=("${API_KEY_ENV_ARGS[@]+"${API_KEY_ENV_ARGS[@]}"}")

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
    # Allow git operations on any directory inside the container.
    # Worktrees are created by different UID across docker run sessions, triggering
    # git's "dubious ownership" check. Safe to disable inside the isolated container.
    setup_lines+='git config --system --add safe.directory "*" 2>/dev/null || git config --global --add safe.directory "*" 2>/dev/null || true'$'\n'
    # Container-local dependency cache directory (see "Dependency caches").
    setup_lines+="mkdir -p $DEPS_PATH && chmod 1777 $DEPS_PATH"$'\n'

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

    # Write mini-swe-agent global config for root (who runs mini via docker exec).
    # Without MSWEA_CONFIGURED=true, mini launches an interactive setup wizard and
    # aborts when stdin is not a TTY. MSWEA_MODEL_NAME is forwarded via docker run -e.
    setup_lines+='if [ -n "${MSWEA_MODEL_NAME:-}" ]; then'$'\n'
    setup_lines+='  mkdir -p /root/.config/mini-swe-agent'$'\n'
    setup_lines+='  { printf "MSWEA_MODEL_NAME='"'"'%s'"'"'\n" "$MSWEA_MODEL_NAME"; echo "MSWEA_CONFIGURED=true"; echo "MSWEA_COST_TRACKING=ignore_errors"; } > /root/.config/mini-swe-agent/.env'$'\n'
    setup_lines+='  echo "[mini-swe-agent] wrote config for root: model=$MSWEA_MODEL_NAME"'$'\n'
    setup_lines+='fi'$'\n'

    # Create non-root user and switch to it (agents like Claude Code refuse root)
    setup_lines+='useradd -m -s /bin/bash bench 2>/dev/null || true'$'\n'
    setup_lines+="chown -R bench:bench $WT_PATH 2>/dev/null"$'\n'
    setup_lines+='[ -d /output ] && chmod -R a+rwX /output 2>/dev/null || true'$'\n'
    setup_lines+='chmod -R a+rX /opt/tools 2>/dev/null || true'$'\n'
    # Copy agent configs to bench user home
    setup_lines+='for d in .claude .aider .config/mini-swe-agent; do'$'\n'
    setup_lines+='  if [ -d "/root/$d" ]; then mkdir -p "/home/bench/$d" && cp -a "/root/$d/." "/home/bench/$d/" 2>/dev/null; chown -R bench:bench "/home/bench/$d" 2>/dev/null; fi'$'\n'
    setup_lines+='done'$'\n'
    setup_lines+='chown -R bench:bench /home/bench 2>/dev/null || true'$'\n'
    # Switch to bench user with correct env (safe.directory already set system-wide above)
    setup_lines+="exec runuser -u bench -- bash -c 'export PATH=\"/opt/tools/bin:\$PATH\" && export HOME=/home/bench && cd $WT_PATH && exec $final_cmd'"$'\n'

    echo "$setup_lines"
}

# ── Benchmark files and builds ───────────────────────────────────────────────

# Write the benchmark-provided files into the worktree: SYMPTOM.md (from the
# case dir) and REBUILD.sh (derived from case.yaml's build command). Used by
# setup and by reset, so a reset always restores pristine copies -- an agent
# may have edited both, and the next agent must not inherit those edits.
install_bench_files() {
    local vol="$1" image="$2" case_dir="$3" build_cmd="$4"
    docker run --rm --network none \
        -v "${vol}:/workspace" \
        -v "${case_dir}/symptom.md:/bench-symptom.md:ro" \
        -e "CASE_WT_PATH=${WT_PATH}" \
        -e "BUILD_CMD=${build_cmd}" \
        "$image" \
        bash -c '
            cp /bench-symptom.md "$CASE_WT_PATH/SYMPTOM.md" || exit 1
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
                elif [ -d build ] && [ -f build/Makefile ]; then
                    # Make build (Kvrocks, RocksDB)
                    # Extract cmake invocation if present (e.g. "cmake .. -DCMAKE_BUILD_TYPE=Debug")
                    # (Trim with sed, not xargs: xargs strips the quotes in e.g.
                    # -DCMAKE_CXX_FLAGS="-include cstdint -w" and breaks the command.)
                    CMAKE_PART=$(echo "$BUILD_CMD" | grep -oP "\bcmake\b\s+[^&]+" | sed -E "s/^[[:space:]]+//; s/[[:space:]]+$//" || echo "")
                    TARGET=$(echo "$BUILD_CMD" | grep -oP "\bmake\b\s+.*?(?=\s*$)" | sed "s/\bmake\b//" | sed -E "s/^[[:space:]]+//; s/[[:space:]]+$//" || echo "")
                    if [ -n "$CMAKE_PART" ]; then
                        REBUILD="cd build && ${CMAKE_PART} && make -j\$(nproc) ${TARGET:-}"
                    else
                        REBUILD="cd build && make -j\$(nproc) ${TARGET:-}"
                    fi
                else
                    # Go (NATS), make at root (etcd), Maven/Gradle/Cargo/erlang.mk:
                    # the full build command.
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
            else
                # No explicit build command — generate a language-specific compile check.
                # This ensures agents have a build contract even for interpreted/scripted projects.
                cd "$CASE_WT_PATH"
                REBUILD_CHECK=""
                if [ -f go.mod ]; then
                    REBUILD_CHECK="go build ./..."
                elif [ -f Cargo.toml ]; then
                    REBUILD_CHECK="cargo build"
                elif [ -f pom.xml ]; then
                    REBUILD_CHECK="mvn compile -q -DskipTests"
                elif [ -f build.gradle ] || [ -f build.gradle.kts ]; then
                    REBUILD_CHECK="./gradlew compileJava -x test --quiet"
                elif [ -f Makefile ]; then
                    REBUILD_CHECK="make"
                fi
                if [ -n "$REBUILD_CHECK" ]; then
                    {
                        printf "#!/usr/bin/env bash\n"
                        printf "set -euo pipefail\n"
                        printf "echo \"Checking build ...\"\n"
                        printf "cd \"\$(dirname \"\${BASH_SOURCE[0]}\")\"\n"
                        printf "%s\n" "$REBUILD_CHECK"
                    } > "$CASE_WT_PATH/REBUILD.sh"
                    chmod +x "$CASE_WT_PATH/REBUILD.sh"
                fi
            fi
        '
}

# Run case.yaml's build command in the worktree. Returns the build's exit code.
# The case directory is deliberately NOT mounted: a build must never copy
# oracle files (harnesses, injected tests) into the agent-visible worktree, and
# setup / reproduce / reset must all build the same way.
# Usage: run_case_build <case> <yaml> <image> <build_cmd> <online|offline> [container-name]
run_case_build() {
    local case_name="$1" yaml="$2" image="$3" build_cmd="$4" mode="$5" name="${6:-}"
    local vol deps_vol
    vol=$(volume_name "$case_name")
    deps_vol=$(deps_volume_name "$case_name")
    build_run_args "$yaml"
    network_args "$mode"
    deps_env_args "$mode"
    local name_args=()
    [ -n "$name" ] && name_args=(--name "$name" "$(case_label_args "$case_name")")
    docker run --rm ${name_args[@]+"${name_args[@]}"} \
        "${RUN_ARGS[@]}" ${NET_ARGS[@]+"${NET_ARGS[@]}"} "${DEPS_ENV[@]}" \
        -v "${vol}:/workspace" \
        -v "${deps_vol}:${DEPS_PATH}" \
        -w "$WT_PATH" \
        -e "BUILD_CMD=${build_cmd}" \
        "$image" \
        bash -c "$CONTAINER_PROLOGUE"'
                 [ -e .git ] || { echo "ERROR: no case repository at $PWD" >&2; exit 97; }
                 eval "$BUILD_CMD"'
}

# ── Commands ─────────────────────────────────────────────────────────────────

cmd_setup() {
    local case_name="$1"; shift
    local warm=true
    while [ $# -gt 0 ]; do
        case "$1" in
            --no-warm) warm=false; shift ;;
            *) die "setup: unknown option $1" ;;
        esac
    done
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
    local vol deps_vol cache_vol legacy
    vol=$(volume_name "$case_name")
    deps_vol=$(deps_volume_name "$case_name")
    cache_vol=$(cache_volume_name "$project")
    legacy=$(legacy_volume_name "$case_name")

    echo "=== bench.sh setup: $case_name ==="
    echo "  Project:  $project"
    echo "  Image:    $image"
    echo "  Volume:   $vol"
    echo "  Deps:     $deps_vol"
    echo "  Cache:    $cache_vol (setup only)"
    echo "  Commit:   $commit"
    echo ""

    if docker volume inspect "$legacy" &>/dev/null; then
        echo "NOTE: volume $legacy is from an older bench.sh layout and is no longer used."
        echo "      List such volumes with: ./bench.sh legacy-volumes"
        echo ""
    fi

    # Step 1: Build Docker image
    ensure_project_image "$project"

    # Step 2: Create volumes and populate the full-history cache
    docker volume create --label "ddbench.case=${case_name}" "$vol" &>/dev/null
    docker volume create --label "ddbench.case=${case_name}" "$deps_vol" &>/dev/null
    docker volume create "$cache_vol" &>/dev/null
    lock_acquire "cache-$project"
    ensure_clone "$project" "$repo" "$image" "$cache_vol"
    lock_release "cache-$project"

    # Step 3: Create this case's repository, truncated to the buggy ancestry
    local existed
    existed=$(case_repo_exists "$vol" "$image")
    ensure_case_repo "$case_name" "$commit" "$image" "$vol" "$cache_vol" "$submodules" "$repo"
    prepare_deps_volume "$deps_vol" "$image"

    local need_warm=false
    if [ "$warm" = true ] && ! deps_warm "$deps_vol" "$image"; then
        need_warm=true
        if [ "$existed" = "yes" ]; then
            echo "Restoring the pristine buggy worktree before warming the dependency cache ..."
            BENCH_RESET_NO_BUILD=1 bash "$SELF" reset "$case_name" >/dev/null \
                || die "reset before warm-up failed; run ./bench.sh reset $case_name to inspect"
        fi
    fi

    # Step 4: Build inside container (online: fills the dependency cache)
    if [ -n "$build_cmd" ]; then
        echo "Building $case_name ..."
        # Retried once: this build downloads toolchains and dependencies, and
        # transient registry/proxy errors are common.
        if ! run_case_build "$case_name" "$yaml" "$image" "$build_cmd" online; then
            echo "Build failed; retrying once ..."
            run_case_build "$case_name" "$yaml" "$image" "$build_cmd" online \
                || die "build failed for $case_name"
        fi
    fi

    # Step 5: Copy benchmark files into the worktree so agents can access
    # them from the workspace without needing access to /bench
    install_bench_files "$vol" "$image" "$case_dir" "$build_cmd"

    # Step 6: Warm-up. Run the oracle once with network access so that every
    # dependency it needs (test-only ones included) lands in the cache; scoring
    # then runs offline. Doubles as a sanity check: the bug must be present.
    if [ "$need_warm" = true ]; then
        echo ""
        echo "Warming the dependency cache (running the oracle once, online) ..."
        local rc attempt
        for attempt in 1 2; do
            rc=0
            ( cmd_reproduce "$case_name" online ) || rc=$?
            [ "$rc" -eq 2 ] && [ "$attempt" -eq 1 ] && { echo "Oracle reported ERROR; retrying the warm-up once ..."; continue; }
            break
        done
        BENCH_RESET_NO_BUILD=1 bash "$SELF" reset "$case_name" >/dev/null \
            || die "reset after warm-up failed; run ./bench.sh reset $case_name to inspect"
        case "$rc" in
            1) echo "Warm-up: the oracle reports FAIL on the buggy code, as expected." ;;
            0) warn "the oracle PASSES on the buggy code (see ./bench.sh validate-oracle $case_name)" ;;
            *) die "warm-up failed: the oracle exited $rc (ERROR). Check the output above and re-run setup." ;;
        esac
        mark_deps_warm "$deps_vol" "$image" "warmed $(now_utc) oracle_exit=$rc"
    elif [ "$warm" = false ]; then
        echo "Skipping the dependency warm-up (--no-warm); reproduce needs network until it runs."
    fi

    echo ""
    echo "=== Setup complete: $case_name ==="
    echo "  Worktree: $WT_PATH (inside volume $vol)"
}

# Exit codes (the contract every reproduce.sh follows, enforced here too):
#   0 = PASS  (bug fixed)
#   1 = FAIL  (bug present, or the worktree does not build)
#   2 = ERROR (infrastructure: case not set up, Docker failure, oracle could not
#              run or was inconclusive)
# Usage: cmd_reproduce <case> [auto|online|offline]
cmd_reproduce() {
    DIE_CODE=2
    local case_name="$1" mode="${2:-auto}"
    local case_dir
    case_dir=$(find_case_dir "$case_name")
    local yaml
    yaml=$(find_case_yaml "$case_dir")

    local project
    project=$(yaml_val "$yaml" "project")
    local image="${IMAGE_PREFIX}/${project}"
    local vol deps_vol
    vol=$(volume_name "$case_name")
    deps_vol=$(deps_volume_name "$case_name")
    local build_cmd
    build_cmd=$(yaml_nested "$yaml" "build" "command")
    local cname
    cname="$(container_name "$case_name")"

    echo "=== bench.sh reproduce: $case_name ==="

    require_case_volume "$case_name"
    docker image inspect "$image" &>/dev/null || die "image $image not found. Run: ./bench.sh setup $case_name"

    if [ "$mode" = "auto" ]; then
        if case_offline "$yaml"; then mode=offline; else mode=online; fi
    fi
    if [ "$mode" = "offline" ] && ! deps_warm "$deps_vol" "$image"; then
        die "the dependency cache of $case_name is not populated (set up by an older bench.sh, or
  setup ran with --no-warm). Scoring runs offline. Run: ./bench.sh setup $case_name"
    fi

    # Rebuild before reproducing (incremental — only recompiles changed files)
    if [ -n "$build_cmd" ]; then
        echo "Rebuilding (incremental) ..."
        local brc=0
        remove_case_container "${cname}-build"
        run_case_build "$case_name" "$yaml" "$image" "$build_cmd" "$mode" "${cname}-build" || brc=$?
        case "$brc" in
            0) ;;
            97)  die "no case repository in volume $vol. Run: ./bench.sh setup $case_name" ;;
            125) die "docker could not start the build container" ;;
            *)   echo ""; echo "FAIL: the worktree does not build (build command exited $brc)"; exit 1 ;;
        esac
    fi

    build_run_args "$yaml"
    network_args "$mode"
    deps_env_args "$mode"

    # Kill any leftover container RIGHT BEFORE starting the named one
    # (not earlier — the rebuild step above can take minutes, during which
    # another process could recreate the container).
    remove_case_container "$cname"

    # Run reproduce.sh in a named container so external scripts can track/kill it
    # on timeout. The --rm flag still ensures cleanup on normal exit.
    # BENCH_WORKDIR is the worktree.
    local rc=0
    docker run --rm --name "$cname" "$(case_label_args "$case_name")" \
        "${RUN_ARGS[@]}" ${NET_ARGS[@]+"${NET_ARGS[@]}"} "${DEPS_ENV[@]}" \
        -v "${vol}:/workspace" \
        -v "${deps_vol}:${DEPS_PATH}" \
        -v "${case_dir}:/bench:ro" \
        -w "$WT_PATH" \
        -e "BENCH_WORKDIR=${WT_PATH}" \
        "$image" \
        bash -c "$CONTAINER_PROLOGUE"'
                 exec bash /bench/reproduce.sh' || rc=$?
    case "$rc" in
        0|1|2) exit "$rc" ;;
        125)   die "docker could not start the reproduce container" ;;
        *)     echo "ERROR: reproduce.sh terminated unexpectedly (exit $rc); verdict inconclusive" >&2; exit 2 ;;
    esac
}

# ── Agent-visible staging (context/, --output-dir) ──────────────────────────
#
# Bind-mount sources are listed in the container's /proc/self/mountinfo, so
# nothing may be bind-mounted from a host path that names the case.

# Copy cases/<case>/context into an opaque read-only volume; echo its name.
stage_context_volume() {
    local case_name="$1" case_dir="$2" image="$3"
    local ctx_vol context_dir="${case_dir}/context" src_mount=()
    ctx_vol=$(context_volume_name "$case_name")
    if [ -d "$context_dir" ]; then
        src_mount=(-v "${context_dir}:/src:ro")
    else
        # Some cases have no debug context; the agent still gets a (empty)
        # ./context directory so the context-condition prompt stays valid.
        echo "WARNING: $case_name has no context/ folder; mounting an empty ./context" >&2
    fi
    docker volume create --label "ddbench.case=${case_name}" "$ctx_vol" >/dev/null
    docker run --rm --network none -v "${ctx_vol}:/ctx" ${src_mount[@]+"${src_mount[@]}"} "$image" \
        sh -c 'find /ctx -mindepth 1 -delete && { [ ! -d /src ] || cp -R /src/. /ctx/; } && chmod -R a+rX /ctx' >/dev/null \
        || die "could not stage context/ into volume $ctx_vol"
    echo "$ctx_vol"
}

# Agent output: /output is an opaque directory under $STATE_DIR. Callers name
# output directories after the case (harness/run_agent.sh uses
# <results>/<case>), so it cannot be bind-mounted directly.
# trajectory.traj.json is symlinked into the requested directory for live
# monitoring; finalize_output replaces the symlink with real copies when the
# agent exits or its container is stopped.
OUTPUT_FILE_NAME="trajectory.traj.json"

new_output_stage() {
    local output_abs="$1" stage
    mkdir -p "$STATE_DIR"
    stage=$(mktemp -d "$STATE_DIR/agent-out.XXXXXXXX")
    chmod 777 "$stage"
    if [ ! -e "$output_abs/$OUTPUT_FILE_NAME" ] || [ -L "$output_abs/$OUTPUT_FILE_NAME" ]; then
        ln -sfn "$stage/$OUTPUT_FILE_NAME" "$output_abs/$OUTPUT_FILE_NAME"
    fi
    echo "$stage"
}

container_label() {
    local v
    v=$(docker inspect -f "{{index .Config.Labels \"$2\"}}" "$1" 2>/dev/null) || return 0
    [ "$v" = "<no value>" ] || echo "$v"
}

# Copy staged agent output of container $1 to its requested output directory.
finalize_output() {
    local cname="$1" stage out src dst
    stage=$(container_label "$cname" ddbench.output-stage)
    out=$(container_label "$cname" ddbench.output-dir)
    [ -n "$stage" ] && [ -n "$out" ] && [ -d "$stage" ] || return 0
    mkdir -p "$out" 2>/dev/null || return 0
    for src in "$stage"/* "$stage"/.[!.]*; do
        [ -e "$src" ] || continue
        dst="$out/$(basename "$src")"
        [ -L "$dst" ] && rm -f "$dst"
        cp -R "$src" "$dst" 2>/dev/null || echo "WARNING: could not copy agent output $src to $out" >&2
    done
    # Drop a dangling live-monitoring symlink if the agent wrote nothing.
    dst="$out/$OUTPUT_FILE_NAME"
    if [ -L "$dst" ] && [ ! -e "$dst" ]; then rm -f "$dst"; fi
    return 0
}

# Stop and remove a case container, saving any staged agent output first.
remove_case_container() {
    local cname="$1" stage
    docker inspect "$cname" &>/dev/null || return 0
    finalize_output "$cname"
    stage=$(container_label "$cname" ddbench.output-stage)
    docker rm -f "$cname" >/dev/null 2>&1 || true
    if [ -n "$stage" ] && [ -d "$stage" ]; then
        case "$stage" in "$STATE_DIR"/agent-out.*) rm -rf "$stage" 2>/dev/null || true ;; esac
    fi
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
    local vol deps_vol
    vol=$(volume_name "$case_name")
    deps_vol=$(deps_volume_name "$case_name")
    local wt_path="$WT_PATH"
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
            "$cname" \
            bash -c 'export PATH="/opt/tools/bin:$PATH" && exec bash'
        return
    fi

    require_case_volume "$case_name"

    # Start a new persistent container
    echo "=== bench.sh shell: $case_name ==="
    [ ${#ADDON_NAMES[@]} -gt 0 ] && echo "  Addons: ${ADDON_NAMES[*]}"
    echo "Type 'exit' to leave the shell (container keeps running)."
    echo "Run './bench.sh stop $case_name' to stop the container."
    echo "Reproduce the bug with: bash /bench/reproduce.sh"
    echo ""

    build_run_args "$yaml"
    deps_env_args online

    if [ ${#ADDON_NAMES[@]} -gt 0 ]; then
        build_addon_args
    fi

    # Pick up context flag from environment (set by harness/run_agent.sh --context)
    if [ "${BENCH_CONTEXT:-}" = "1" ]; then
        AGENT_CONTEXT=true
    fi

    # Mount debug-context folder (read-only) into the worktree if --context is set
    if [ "$AGENT_CONTEXT" = true ]; then
        local ctx_vol
        ctx_vol=$(stage_context_volume "$case_name" "$case_dir" "$image")
        RUN_ARGS+=("-v" "${ctx_vol}:${wt_path}/context:ro")
    fi

    # A shell is a human session: it mounts the case dir at /bench so that
    # `bash /bench/reproduce.sh` works, and the case's dependency cache. It is
    # never reused for `bench.sh agent`.
    docker volume create --label "ddbench.case=${case_name}" "$deps_vol" &>/dev/null
    docker run -d \
        --name "$cname" "$(case_label_args "$case_name")" \
        "${RUN_ARGS[@]}" "${DEPS_ENV[@]}" \
        -v "${vol}:/workspace" \
        -v "${deps_vol}:${DEPS_PATH}" \
        -v "${case_dir}:/bench:ro" \
        -w "$wt_path" \
        -e "BENCH_WORKDIR=${wt_path}" \
        "$image" \
        sleep infinity >/dev/null
    docker exec "$cname" sh -c 'git config --global --add safe.directory "*" 2>/dev/null' || true

    # Run addon setup inside the container (as root)
    if [ ${#ADDON_NAMES[@]} -gt 0 ]; then
        local entrypoint
        entrypoint=$(addon_entrypoint "true")
        docker exec ${API_KEY_ENV_ARGS[@]+"${API_KEY_ENV_ARGS[@]}"} "$cname" bash -c "$entrypoint"
    fi

    # Exec into the container
    docker exec -it -w "$wt_path" \
        "$cname" \
        bash -c 'export PATH="/opt/tools/bin:$PATH" && exec bash'
}

cmd_agent() {
    local case_name="$1"
    shift
    parse_addons "$@"

    [ ${#ADDON_NAMES[@]} -gt 0 ] || die "agent command requires at least one --addon flag"

    # Pick up context flag from environment (set by harness/run_agent.sh --context)
    if [ "${BENCH_CONTEXT:-}" = "1" ]; then
        AGENT_CONTEXT=true
    fi

    local case_dir
    case_dir=$(find_case_dir "$case_name")
    local yaml
    yaml=$(find_case_yaml "$case_dir")

    local project
    project=$(yaml_val "$yaml" "project")
    local image="${IMAGE_PREFIX}/${project}"
    local vol
    vol=$(volume_name "$case_name")
    local wt_path="$WT_PATH"
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
                if [ -n "$AGENT_CONFIG" ]; then
                    # Include mini.yaml FIRST so its model/defaults are preserved;
                    # our config merges on top. Without mini.yaml, -c replaces the
                    # default entirely and the model is unset → silent crash.
                    mini_args="$mini_args --config mini.yaml --config /configs/agent_config.yaml"
                fi
                # Also pass model explicitly in case env isn't picked up
                [ -n "${MSWEA_MODEL_NAME:-}" ] && mini_args="$mini_args -m \"${MSWEA_MODEL_NAME}\""
                # Write trajectory to a mounted output directory for host-side monitoring
                if [ -n "$AGENT_OUTPUT_DIR" ]; then
                    mini_args="$mini_args -o /output/$OUTPUT_FILE_NAME"
                fi
                final_cmd="mini $mini_args -t \"$AGENT_PROMPT\""
                ;;
            *)      final_cmd="$agent_cmd" ;;
        esac
    fi

    echo "=== bench.sh agent: $case_name ==="
    echo "  Addons: ${ADDON_NAMES[*]}"
    [ -n "$AGENT_PROMPT" ] && echo "  Prompt: ${AGENT_PROMPT:0:80}..."
    [ -n "$AGENT_OUTPUT_DIR" ] && echo "  Output: $AGENT_OUTPUT_DIR/$OUTPUT_FILE_NAME"
    echo ""

    # Never reuse a container that exposes the case dir (e.g. one started by
    # `bench.sh shell`, which mounts /bench): recreate it without the oracle.
    if container_running "$cname" && \
       docker inspect -f '{{range .Mounts}}{{.Destination}}{{"\n"}}{{end}}' "$cname" 2>/dev/null | grep -qx '/bench'; then
        echo "Running container for $case_name mounts /bench (case files); recreating it for the agent ..."
        remove_case_container "$cname"
    fi

    # Save staged output whenever this command ends (normally, or killed by a
    # timeout: `timeout` signals the whole process group).
    trap 'finalize_output "'"$cname"'"' EXIT
    trap 'finalize_output "'"$cname"'"; exit 143' TERM
    trap 'finalize_output "'"$cname"'"; exit 130' INT

    # Reuse running container if available
    if container_running "$cname"; then
        if [ "$AGENT_CONTEXT" = true ]; then
            if [ "$AGENT_FORCE" = true ]; then
                # --force: stop and recreate the container for context mount
                echo "Stopping running container (--force: recreating for context mount) ..."
                remove_case_container "$cname"
            else
                echo "WARNING: Container for $case_name is already running." >&2
                echo "  context/ cannot be mounted into an existing container." >&2
                echo "  The agent will run WITHOUT debug context." >&2
                echo "  To recreate the container with debug context, add --force:" >&2
                echo "    bench.sh agent $case_name --context --force ..." >&2
                echo "" >&2
            fi
        fi

        if container_running "$cname"; then
            echo "Attaching to running container ..."
            # Only allocate a TTY (-t) if stdout is a real terminal.
            # Without this, `docker exec -it` exits silently when stdout is redirected.
            local tty_flag=""
            [ -t 1 ] && tty_flag="-t"
            docker exec -i $tty_flag -w "$wt_path" \
                -e "PYTHONUNBUFFERED=1" \
                ${API_KEY_ENV_ARGS[@]+"${API_KEY_ENV_ARGS[@]}"} \
                "$cname" \
                bash -c "export PATH=/opt/tools/bin:\$PATH && exec $final_cmd"
            return
        fi
    fi

    require_case_volume "$case_name"
    remove_case_container "$cname"   # a stopped leftover would block the name

    # Start a new persistent container
    build_run_args "$yaml"
    build_addon_args
    # Same package-manager locations as scoring, but $DEPS_PATH is an empty
    # directory inside this container: the case's dependency volume is never
    # mounted for agents (see "Dependency caches").
    deps_env_args online
    RUN_ARGS+=("${DEPS_ENV[@]}")

    # Agents must not get the host ~/.claude: its session transcripts (projects/),
    # file-history/, history and memory can contain case solutions. Drop that
    # mount; the claude-code addon gets only its auth and settings files.
    local _filtered=() _i
    for ((_i = 0; _i < ${#RUN_ARGS[@]}; _i++)); do
        if [ "${RUN_ARGS[$_i]}" = "-v" ] && [ "${RUN_ARGS[$((_i + 1))]:-}" = "${HOME}/.claude:/root/.claude:ro" ]; then
            _i=$((_i + 1)); continue
        fi
        _filtered+=("${RUN_ARGS[$_i]}")
    done
    RUN_ARGS=("${_filtered[@]}")
    if [[ " ${ADDON_NAMES[*]} " == *" claude-code "* ]]; then
        local _f
        for _f in .credentials.json settings.json; do
            [ -f "$HOME/.claude/$_f" ] && RUN_ARGS+=("-v" "$HOME/.claude/$_f:/root/.claude/$_f:ro")
        done
    fi

    # Mount agent config file if provided
    if [ -n "$AGENT_CONFIG" ]; then
        local config_abs
        config_abs=$(cd "$(dirname "$AGENT_CONFIG")" && pwd)/$(basename "$AGENT_CONFIG")
        [ -f "$config_abs" ] || die "Config file not found: $AGENT_CONFIG"
        RUN_ARGS+=("-v" "${config_abs}:/configs/agent_config.yaml:ro")
    fi

    # Output directory for trajectory files (host-side monitoring), via an
    # opaque staging directory (see new_output_stage).
    if [ -n "$AGENT_OUTPUT_DIR" ]; then
        local output_abs stage
        output_abs=$(mkdir -p "$AGENT_OUTPUT_DIR" && cd "$AGENT_OUTPUT_DIR" && pwd)
        stage=$(new_output_stage "$output_abs")
        RUN_ARGS+=("-v" "${stage}:/output"
                   "--label" "ddbench.output-stage=${stage}"
                   "--label" "ddbench.output-dir=${output_abs}")
    fi

    # Debug-context folder (read-only) at ./context if --context is set
    if [ "$AGENT_CONTEXT" = true ]; then
        local ctx_vol
        ctx_vol=$(stage_context_volume "$case_name" "$case_dir" "$image")
        RUN_ARGS+=("-v" "${ctx_vol}:${wt_path}/context:ro")
    fi

    # Host network mode: lets the container reach services on the host's
    # localhost (e.g., SSH port-forwarded vLLM/inference servers).
    if [ "${BENCH_HOST_NETWORK:-}" = "1" ]; then
        RUN_ARGS+=("--network" "host")
        # Ensure host.docker.internal resolves to 127.0.0.1 so configs using
        # that hostname also work under --network host.
        RUN_ARGS+=("--add-host=host.docker.internal:127.0.0.1")
    fi

    # The case dir (reproduce.sh, oracle harness files, context/, docs) is
    # deliberately NOT mounted: agents must never see the oracle. They get
    # SYMPTOM.md in the worktree (copied at setup) and context/ only via --context.
    # Scoring (cmd_reproduce) runs the oracle in its own container with /bench.
    # No case-specific environment variables, paths or names (see "Opaque case
    # identity" at the top of this file).
    docker run -d \
        --name "$cname" "$(case_label_args "$case_name")" \
        "${RUN_ARGS[@]}" \
        -v "${vol}:/workspace" \
        -w "$wt_path" \
        "$image" \
        sleep infinity >/dev/null

    # Run addon setup inside the container (as root)
    local entrypoint
    entrypoint=$(addon_entrypoint "true")
    docker exec ${API_KEY_ENV_ARGS[@]+"${API_KEY_ENV_ARGS[@]}"} "$cname" bash -c "$entrypoint"

    # Launch agent
    # Only allocate a TTY (-t) if stdout is a real terminal.
    # Without this, `docker exec -it` exits silently when stdout is redirected (e.g., to a log file).
    local tty_flag=""
    [ -t 1 ] && tty_flag="-t"
    docker exec -i $tty_flag -w "$wt_path" \
        -e "PYTHONUNBUFFERED=1" \
        ${API_KEY_ENV_ARGS[@]+"${API_KEY_ENV_ARGS[@]}"} \
        "$cname" \
        bash -c "export PATH=/opt/tools/bin:\$PATH && exec $final_cmd"
}

cmd_stop() {
    local case_name="$1"
    local cname
    cname=$(container_name "$case_name")

    if container_running "$cname"; then
        echo "Stopping container $cname ..."
        remove_case_container "$cname"
        echo "Stopped."
    elif docker inspect "$cname" &>/dev/null; then
        echo "Container $cname exists but is not running. Removing ..."
        remove_case_container "$cname"
        echo "Removed."
    else
        echo "No running container for $case_name."
    fi
}

# Network mode for builds outside setup: offline once the cache is warm.
build_mode() {
    local case_name="$1" yaml="$2" image="$3"
    if case_offline "$yaml" && deps_warm "$(deps_volume_name "$case_name")" "$image"; then
        echo offline
    else
        echo online
    fi
}

cmd_rebuild() {
    local case_name="$1"
    local case_dir
    case_dir=$(find_case_dir "$case_name")
    local yaml
    yaml=$(find_case_yaml "$case_dir")

    local project
    project=$(yaml_val "$yaml" "project")
    local image="${IMAGE_PREFIX}/${project}"
    local vol deps_vol mode
    vol=$(volume_name "$case_name")
    deps_vol=$(deps_volume_name "$case_name")
    require_case_volume "$case_name"
    mode=$(build_mode "$case_name" "$yaml" "$image")

    echo "=== bench.sh rebuild: $case_name ($mode) ==="

    build_run_args "$yaml"
    network_args "$mode"
    deps_env_args "$mode"

    docker run --rm \
        "${RUN_ARGS[@]}" ${NET_ARGS[@]+"${NET_ARGS[@]}"} "${DEPS_ENV[@]}" \
        -v "${vol}:/workspace" \
        -v "${deps_vol}:${DEPS_PATH}" \
        -w "$WT_PATH" \
        -e "CASE_WT_PATH=${WT_PATH}" \
        "$image" \
        bash -c "$CONTAINER_PROLOGUE"'
            if [ -f "$CASE_WT_PATH/REBUILD.sh" ]; then
                bash "$CASE_WT_PATH/REBUILD.sh"
            else
                echo "No REBUILD.sh found in worktree (skipping)."
            fi
        '
}

cmd_reset() {
    local case_name="$1"
    local case_dir
    case_dir=$(find_case_dir "$case_name")
    local yaml
    yaml=$(find_case_yaml "$case_dir")

    local project submodules commit build_cmd
    project=$(yaml_val "$yaml" "project")
    submodules=$(yaml_val "$yaml" "submodules")
    commit=$(yaml_val "$yaml" "buggy_commit")
    build_cmd=$(yaml_nested "$yaml" "build" "command")
    local image="${IMAGE_PREFIX}/${project}"
    local vol
    vol=$(volume_name "$case_name")
    require_case_volume "$case_name"

    echo "=== bench.sh reset: $case_name ==="
    echo "Reverting to the original buggy commit ($commit)..."

    # Resolve the buggy commit to a SHA from the cache. The case repo is truncated
    # (no refs, fix commit absent), so "<fix>~1" can't be resolved inside it. This
    # container mounts only the cache, never the worktree.
    local cache_vol resolved
    cache_vol=$(cache_volume_name "$project")
    resolved=$(docker run --rm --network none -v "${cache_vol}:/cache:ro" -e "CACHE_GIT_DIR=${CACHE_GIT_DIR}" "$image" \
        bash -c 'git config --global --add safe.directory "*" 2>/dev/null; git --git-dir="$CACHE_GIT_DIR" rev-parse --verify "$1^{commit}"' -- "$commit") \
        || die "Cannot resolve buggy commit $commit from cache volume $cache_vol (run setup first)."

    docker run --rm --network none \
        -v "${vol}:/workspace" \
        -e "CASE_WT_PATH=${WT_PATH}" \
        -e "CASE_COMMIT=${commit}" \
        -e "CASE_COMMIT_SHA=${resolved}" \
        -e "CASE_SUBMODULES=${submodules}" \
        "$image" \
        bash -c '
            cd "$CASE_WT_PATH" || exit 1
            # Mark all directories safe: worktrees were chowned to the bench user
            # during agent execution, causing git dubious-ownership errors as root.
            git config --system --add safe.directory "*" 2>/dev/null || \
                git config --global --add safe.directory "*" 2>/dev/null || true

            # Step 1: Clean working tree (discard all modifications)
            git checkout -- .
            git clean -fd

            # Oracle runs leave reports, logs and binaries built from injected
            # tests in gitignored paths, where the next agent would find them.
            find . -path ./.git -prune -o -type d \( -name surefire-reports -o -name failsafe-reports \
                 -o -name "ct_run.*" -o -path "*/build/test-results" -o -path "*/build/reports/tests" \) \
                 -prune -exec rm -rf {} + 2>/dev/null
            find . -path ./.git -prune -o \( -iname "*ddbench*oracle*" -o -path "*/target/debug/deps/tests-*" \
                 -o -path "*/target/debug/incremental/tests-*" \) -prune -exec rm -rf {} + 2>/dev/null
            for d in logs deps/*/logs; do
                [ -e "$d" ] || continue
                git ls-files --error-unmatch "$d" >/dev/null 2>&1 || rm -rf "$d"
            done

            # Step 2: Move HEAD back to the buggy commit (e.g. after an agent
            # committed or checked out something else), and drop any refs created
            # since setup: the truncated repo has none by design.
            if [ "$(git rev-parse HEAD)" != "$CASE_COMMIT_SHA" ]; then
                echo "HEAD was at $(git rev-parse --short HEAD), checking out $CASE_COMMIT ..."
                git checkout -q --detach "$CASE_COMMIT_SHA" || exit 1
            fi
            git for-each-ref --format="%(refname)" | while read -r ref; do git update-ref -d "$ref"; done
            git stash clear 2>/dev/null || true
            git reflog expire --expire=now --all 2>/dev/null || true

            # Step 3: Reset submodules if applicable
            if [ "$CASE_SUBMODULES" = "true" ]; then
                git submodule update --init --recursive 2>&1 | tail -1
                git submodule foreach --recursive git checkout -- .
                git submodule foreach --recursive git clean -fd
            fi
        '

    # Step 4: Restore pristine SYMPTOM.md / REBUILD.sh (an agent may have
    # edited them; the next agent must not inherit those edits).
    install_bench_files "$vol" "$image" "$case_dir" "$build_cmd"

    # Step 5: Rebuild, so the binaries in the volume match the buggy source again.
    # Without this, artifacts built from a previous run's (possibly fixed) source
    # would survive the reset and be visible to -- and runnable by -- the next agent.
    if [ -n "$build_cmd" ] && [ "${BENCH_RESET_NO_BUILD:-}" != "1" ]; then
        echo "Rebuilding the buggy source ..."
        run_case_build "$case_name" "$yaml" "$image" "$build_cmd" "$(build_mode "$case_name" "$yaml" "$image")" \
            >/dev/null 2>&1 \
            || echo "WARNING: rebuild after reset failed; run './bench.sh rebuild $case_name' to inspect." >&2
    fi

    echo "Reset complete. Source is back to the original buggy state."
    echo "Run './bench.sh reproduce $case_name' to verify the bug is still present."
}

cmd_clean() {
    local case_name="$1"
    find_case_dir "$case_name" >/dev/null

    local vol ctx_vol deps_vol legacy
    vol=$(volume_name "$case_name")
    ctx_vol=$(context_volume_name "$case_name")
    deps_vol=$(deps_volume_name "$case_name")
    legacy=$(legacy_volume_name "$case_name")

    remove_case_container "$(container_name "$case_name")"
    remove_case_container "$(container_name "$case_name")-build"

    local v found=false
    for v in "$vol" "$ctx_vol" "$deps_vol" "$legacy"; do
        docker volume inspect "$v" &>/dev/null || continue
        found=true
        # Stop and remove any containers that use this volume (includes VS Code devcontainers)
        local -a using
        mapfile -t using < <(docker ps -aq --filter "volume=${v}" 2>/dev/null || true)
        for cid in "${using[@]}"; do
            [ -z "$cid" ] && continue
            echo "Stopping container $cid ..."
            docker stop "$cid" 2>/dev/null || true
            docker rm "$cid" 2>/dev/null || true
        done
        # Each case owns its volumes, so they go entirely. The per-project cache
        # volume is deliberately left alone — it is shared and expensive to rebuild.
        echo "Removing volume $v ..."
        docker volume rm "$v" &>/dev/null || echo "WARNING: could not remove volume $v (in use?)"
    done
    $found || echo "No volumes for $case_name. Nothing to clean."
    echo "Cleaned $case_name."
}

# Print the Docker objects and paths bench.sh uses for a case, as key=value
# lines, or just the value of one field. For tooling (e.g. patch extraction).
cmd_info() {
    local case_name="$1" field="${2:-}"
    local case_dir yaml project mode
    case_dir=$(find_case_dir "$case_name")
    yaml=$(find_case_yaml "$case_dir")
    project=$(yaml_val "$yaml" "project")
    resolve_cpus "$yaml" 2>/dev/null
    if case_offline "$yaml"; then mode=none; else mode=default; fi
    local -a kv=(
        "uid=$(case_uid "$case_name")"
        "project=${project}"
        "volume=$(volume_name "$case_name")"
        "context_volume=$(context_volume_name "$case_name")"
        "deps_volume=$(deps_volume_name "$case_name")"
        "cache_volume=$(cache_volume_name "$project")"
        "container=$(container_name "$case_name")"
        "image=${IMAGE_PREFIX}/${project}"
        "workdir=${WT_PATH}"
        "deps_path=${DEPS_PATH}"
        "cpus=${EFFECTIVE_CPUS}"
        "scoring_network=${mode}"
    )
    local line
    for line in "${kv[@]}"; do
        if [ -z "$field" ]; then echo "$line"
        elif [ "${line%%=*}" = "$field" ]; then echo "${line#*=}"; return 0; fi
    done
    # buggy_sha: the buggy commit resolved to a SHA (needs the project cache
    # volume, i.e. a completed setup); only printed when asked for.
    if [ "$field" = "buggy_sha" ]; then
        local commit
        commit=$(yaml_val "$yaml" "buggy_commit")
        docker run --rm --network none -v "$(cache_volume_name "$project"):/cache:ro" \
            -e "CACHE_GIT_DIR=${CACHE_GIT_DIR}" "${IMAGE_PREFIX}/${project}" \
            bash -c 'git config --global --add safe.directory "*" 2>/dev/null; git --git-dir="$CACHE_GIT_DIR" rev-parse --verify "$1^{commit}"' -- "$commit" \
            || die "cannot resolve $commit (run ./bench.sh setup $case_name first)"
        return 0
    fi
    [ -z "$field" ] || die "unknown field: $field"
}

# Build (or refresh, if a Dockerfile changed) project images: all, or the given ones.
cmd_build_images() {
    local p
    local -a projects=("$@")
    if [ ${#projects[@]} -eq 0 ]; then
        mapfile -t projects < <(for d in "$REPO_ROOT"/cases/*/case.yaml; do yaml_val "$d" project; done | sort -u)
    fi
    for p in "${projects[@]}"; do
        echo "--- image ${IMAGE_PREFIX}/$p"
        ensure_project_image "$p"
    done
}

cmd_list() {
    local vols d n project status
    vols=$(docker volume ls -q --filter "name=${IMAGE_PREFIX}-ws-" 2>/dev/null || true)
    printf '%-48s %-11s %s\n' "CASE" "PROJECT" "STATUS"
    for d in "$REPO_ROOT"/cases/*/; do
        n=$(basename "$d")
        [ -f "$d/case.yaml" ] || continue
        project=$(yaml_val "$d/case.yaml" "project")
        if printf '%s\n' "$vols" | grep -qx "$(volume_name "$n")"; then status="set up"; else status="-"; fi
        printf '%-48s %-11s %s\n' "$n" "$project" "$status"
    done
}

# Volumes created by older bench.sh layouts. Current volumes are
# bug-bench-{ws,ctx,deps}-<uid>, bug-bench-<project>-cache and bug-bench-tools.
cmd_legacy_volumes() {
    local remove=false
    case "${1:-}" in
        "") ;;
        --remove) remove=true ;;
        *) die "Usage: bench.sh legacy-volumes [--remove]" ;;
    esac
    local -a vols legacy=()
    mapfile -t vols < <(docker volume ls -q | grep "^${IMAGE_PREFIX}-" || true)
    local v p
    for v in "${vols[@]}"; do
        [ -n "$v" ] || continue
        case "$v" in
            "${IMAGE_PREFIX}"-ws-*|"${IMAGE_PREFIX}"-ctx-*|"${IMAGE_PREFIX}"-deps-*|"$TOOLS_VOL") continue ;;
            "${IMAGE_PREFIX}"-*-cache)
                p=${v#"${IMAGE_PREFIX}"-}; p=${p%-cache}
                [ -f "$(dockerfile_path "$p")" ] && continue ;;
        esac
        legacy+=("$v")
    done
    if [ ${#legacy[@]} -eq 0 ]; then echo "No legacy bug-bench volumes."; return 0; fi
    if [ "$remove" = false ]; then
        echo "Volumes left by older bench.sh layouts (not used by this version):"
        printf '  %s\n' "${legacy[@]}"
        echo ""
        echo "They may still hold earlier experiment state. Remove them with:"
        echo "  ./bench.sh legacy-volumes --remove"
        return 0
    fi
    for v in "${legacy[@]}"; do
        if [ -n "$(docker ps -aq --filter "volume=$v" 2>/dev/null)" ]; then
            echo "Skipping $v (used by a container)"; continue
        fi
        echo "Removing $v ..."
        docker volume rm "$v" >/dev/null || echo "WARNING: could not remove $v"
    done
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

# ── Evaluation: eval / validate-oracle / eval-all ────────────────────────────
#
# These commands drive `bench.sh reset` and `bench.sh reproduce` as
# subprocesses, so each oracle run is exactly what `bench.sh reproduce` does.
#
# Per-run verdicts: exit 0 = PASS, 1 = FAIL, 2 = ERROR. A run that exceeds
# --timeout is killed and counts as FAIL (timed_out: true): the code under test
# did not finish within the limit.

verdict_of() {  # <exit-code> <timed_out> -> PASS|FAIL|ERROR
    if [ "$2" = true ]; then echo FAIL; return; fi
    case "$1" in 0) echo PASS ;; 1) echo FAIL ;; *) echo ERROR ;; esac
}

verdict_exit() {  # <verdict> -> exit code
    case "$1" in PASS) echo 0 ;; FAIL) echo 1 ;; *) echo 2 ;; esac
}

# Last PASS:/FAIL:/ERROR:/TIMEOUT: line of a log (else its last line).
summary_line() {
    local s
    s=$(grep -E '^(PASS|FAIL|ERROR|TIMEOUT)[: ]' "$1" 2>/dev/null | tail -n 1 || true)
    [ -n "$s" ] || s=$(grep -v '^[[:space:]]*$' "$1" 2>/dev/null | tail -n 1 || true)
    printf '%s' "${s:0:300}"
}

parse_positive_int() {  # <option> <value>
    [[ "$2" =~ ^[0-9]+$ ]] && [ "$2" -ge 1 ] || die "$1 expects a positive integer, got '$2'"
}

# run_series <case> <n> <label> <log-dir> <timeout-seconds>
# Runs `bench.sh reproduce` n times; fills the SER_* arrays.
run_series() {
    local case_name="$1" n="$2" label="$3" log_dir="$4" tmo="$5"
    local i rc t0 dur log to cname
    SER_RC=(); SER_TO=(); SER_DUR=(); SER_SUM=(); SER_LOG=(); SER_VERDICT=()
    cname=$(container_name "$case_name")
    if [ "$tmo" -gt 0 ] && ! command -v timeout &>/dev/null; then
        warn "'timeout' (GNU coreutils) not found: oracle runs are not time-limited"
        tmo=0
    fi
    for ((i = 1; i <= n; i++)); do
        log="$log_dir/$label-run$i.log"
        t0=$(date +%s); rc=0; to=false
        if [ "$tmo" -gt 0 ]; then
            timeout --kill-after=30 "$tmo" bash "$SELF" reproduce "$case_name" >"$log" 2>&1 || rc=$?
            if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then
                to=true
                docker rm -f "$cname" "$cname-build" >/dev/null 2>&1 || true
                echo "TIMEOUT: the oracle did not finish within ${tmo}s" >>"$log"
            fi
        else
            bash "$SELF" reproduce "$case_name" >"$log" 2>&1 || rc=$?
        fi
        dur=$(( $(date +%s) - t0 ))
        SER_RC+=("$rc"); SER_TO+=("$to"); SER_DUR+=("$dur"); SER_LOG+=("$log")
        SER_SUM+=("$(summary_line "$log")")
        SER_VERDICT+=("$(verdict_of "$rc" "$to")")
        printf '  [%s %d/%d] %-5s exit=%s %ss  %s\n' "$label" "$i" "$n" "${SER_VERDICT[-1]}" "$rc" "$dur" "${SER_SUM[-1]:0:100}"
    done
}

series_json() {  # SER_* arrays -> JSON array of runs
    local i sep="" out="["
    for i in "${!SER_RC[@]}"; do
        out+="$sep{\"run\": $((i + 1)), \"verdict\": \"${SER_VERDICT[$i]}\", \"exit_code\": ${SER_RC[$i]},"
        out+=" \"timed_out\": ${SER_TO[$i]}, \"duration_s\": ${SER_DUR[$i]},"
        out+=" \"summary\": $(json_str "${SER_SUM[$i]}"), \"log\": $(json_str "${SER_LOG[$i]}")}"
        sep=", "
    done
    printf '%s]' "$out"
}

series_codes_json() { local IFS=,; printf '[%s]' "${SER_RC[*]}"; }

count_verdict() {  # <verdict> -> how many SER_VERDICT entries match
    local v c=0
    for v in "${SER_VERDICT[@]}"; do [ "$v" = "$1" ] && c=$((c + 1)); done
    echo "$c"
}

# Aggregate verdict over runs: any FAIL => FAIL (a definite failure is
# conclusive), else any ERROR => ERROR (inconclusive), else PASS.
series_verdict() {
    if [ "$(count_verdict FAIL)" -gt 0 ]; then echo FAIL
    elif [ "$(count_verdict ERROR)" -gt 0 ]; then echo ERROR
    else echo PASS; fi
}

# apply_patch <case> <patch-file> <log> -> 0 applied, 1 does not apply, 2 error
apply_patch() {
    local case_name="$1" patch="$2" log="$3" yaml project image vol abs rc=0
    yaml=$(find_case_yaml "$(find_case_dir "$case_name")")
    project=$(yaml_val "$yaml" "project")
    image="${IMAGE_PREFIX}/${project}"
    vol=$(volume_name "$case_name")
    abs="$(cd "$(dirname "$patch")" && pwd)/$(basename "$patch")"
    docker run --rm --network none \
        -v "${vol}:/workspace" -v "${abs}:/tmp/ddbench.patch:ro" -w "$WT_PATH" "$image" \
        bash -c '
            git config --global --add safe.directory "*" 2>/dev/null
            if ! grep -q "[^[:space:]]" /tmp/ddbench.patch; then
                echo "empty patch: nothing to apply"; exit 0
            fi
            git apply --check --verbose --whitespace=nowarn /tmp/ddbench.patch || exit 10
            git apply --verbose --whitespace=nowarn /tmp/ddbench.patch || exit 10
        ' >"$log" 2>&1 || rc=$?
    case "$rc" in 0) return 0 ;; 10) return 1 ;; *) return 2 ;; esac
}

# Write $2 (JSON text) to file $1, or to stdout when $1 is "-".
emit_json() {
    if [ "$1" = "-" ]; then printf '%s\n' "$2"
    elif [ -n "$1" ]; then mkdir -p "$(dirname "$1")"; printf '%s\n' "$2" >"$1"; fi
}

default_log_dir() {  # <kind> <case>
    local d
    d="$STATE_DIR/logs/$1-$2-$(date -u +%Y%m%dT%H%M%SZ)-$$"
    mkdir -p "$d"
    echo "$d"
}

cmd_eval() {
    local case_name="$1"; shift
    local patch="" runs=1 json="" log_dir="" tmo="${BENCH_RUN_TIMEOUT:-$DEFAULT_RUN_TIMEOUT}" do_reset=true
    while [ $# -gt 0 ]; do
        case "$1" in
            --patch)    [ -n "${2:-}" ] || die "--patch requires a file"; patch="$2"; shift 2 ;;
            --runs)     parse_positive_int --runs "${2:-}"; runs="$2"; shift 2 ;;
            --json)     [ -n "${2:-}" ] || die "--json requires a path"; json="$2"; shift 2 ;;
            --log-dir)  [ -n "${2:-}" ] || die "--log-dir requires a path"; log_dir="$2"; shift 2 ;;
            --timeout)  [[ "${2:-}" =~ ^[0-9]+$ ]] || die "--timeout expects seconds (0 = none)"; tmo="$2"; shift 2 ;;
            --no-reset) do_reset=false; shift ;;
            *) die "eval: unknown option $1 (see ./bench.sh help)" ;;
        esac
    done
    [ -n "$patch" ] || die "eval: --patch <file.diff> is required"
    find_case_dir "$case_name" >/dev/null
    [ -n "$log_dir" ] || log_dir=$(default_log_dir eval "$case_name")
    mkdir -p "$log_dir"; log_dir=$(cd "$log_dir" && pwd)

    local t0 started applied=false apply_rc=0 err="" verdict patch_sha="" apply_out=""
    t0=$(date +%s); started=$(now_utc)
    SER_RC=(); SER_TO=(); SER_DUR=(); SER_SUM=(); SER_LOG=(); SER_VERDICT=()

    echo "=== bench.sh eval: $case_name ($runs run(s)) ==="
    if [ ! -f "$patch" ]; then
        err="patch file not found: $patch"
    elif ! docker volume inspect "$(volume_name "$case_name")" &>/dev/null; then
        err="$case_name is not set up. Run: ./bench.sh setup $case_name"
    fi
    if [ -z "$err" ]; then
        patch_sha=$(sha256_hex <"$patch")
        echo "  Resetting the worktree to the buggy commit ..."
        if ! BENCH_RESET_NO_BUILD=1 bash "$SELF" reset "$case_name" >"$log_dir/reset-before.log" 2>&1; then
            err="reset before applying the patch failed (see $log_dir/reset-before.log)"
        fi
    fi
    if [ -z "$err" ]; then
        apply_patch "$case_name" "$patch" "$log_dir/apply.log" || apply_rc=$?
        case "$apply_rc" in
            0) applied=true; echo "  Patch applied." ;;
            1) apply_out=$(tail -n 20 "$log_dir/apply.log")
               echo "  Patch does NOT apply to the buggy commit:"; sed 's/^/    /' "$log_dir/apply.log" | tail -n 20 ;;
            *) err="could not apply the patch (docker error, see $log_dir/apply.log)" ;;
        esac
    fi

    if [ -n "$err" ]; then
        verdict=ERROR
        echo "ERROR: $err" >&2
    elif [ "$applied" = false ]; then
        verdict=FAIL
    else
        run_series "$case_name" "$runs" eval "$log_dir" "$tmo"
        verdict=$(series_verdict)
    fi

    local reset_ok=null
    if [ "$do_reset" = true ] && [ -z "$err" ]; then
        echo "  Resetting the worktree (and rebuilding the buggy source) ..."
        if bash "$SELF" reset "$case_name" >"$log_dir/reset-after.log" 2>&1; then reset_ok=true; else reset_ok=false; fi
    fi

    local out
    out="{\"schema\": \"ddbench.eval/v1\", \"case\": $(json_str "$case_name"), \"verdict\": \"$verdict\","
    out+=" \"exit_code\": $(verdict_exit "$verdict"), \"exit_codes\": $(series_codes_json),"
    out+=" \"n_runs\": $runs, \"runs\": $(series_json),"
    out+=" \"patch_applied\": $applied, \"patch_file\": $(json_str "$patch"), \"patch_sha256\": $(json_str "$patch_sha"),"
    out+=" \"apply_output\": $(json_str "$apply_out"),"
    if [ -n "$err" ]; then out+=" \"error\": $(json_str "$err"),"; else out+=" \"error\": null,"; fi
    out+=" \"reset_after\": $reset_ok, \"timeout_s\": $tmo, \"log_dir\": $(json_str "$log_dir"),"
    out+=" \"duration_s\": $(( $(date +%s) - t0 )), \"started_at\": \"$started\", \"timestamp\": \"$(now_utc)\"}"
    emit_json "$json" "$out"

    echo "=== eval $case_name: $verdict ==="
    exit "$(verdict_exit "$verdict")"
}

cmd_validate_oracle() {
    local case_name="$1"; shift
    local runs=1 json="" log_dir="" tmo="${BENCH_RUN_TIMEOUT:-$DEFAULT_RUN_TIMEOUT}"
    while [ $# -gt 0 ]; do
        case "$1" in
            --runs)    parse_positive_int --runs "${2:-}"; runs="$2"; shift 2 ;;
            --json)    [ -n "${2:-}" ] || die "--json requires a path"; json="$2"; shift 2 ;;
            --log-dir) [ -n "${2:-}" ] || die "--log-dir requires a path"; log_dir="$2"; shift 2 ;;
            --timeout) [[ "${2:-}" =~ ^[0-9]+$ ]] || die "--timeout expects seconds (0 = none)"; tmo="$2"; shift 2 ;;
            *) die "validate-oracle: unknown option $1 (see ./bench.sh help)" ;;
        esac
    done
    find_case_dir "$case_name" >/dev/null
    local gold="$REPO_ROOT/cases-solution/$case_name/gold.patch"
    [ -n "$log_dir" ] || log_dir=$(default_log_dir validate "$case_name")
    mkdir -p "$log_dir"; log_dir=$(cd "$log_dir" && pwd)

    local t0 started err="" status detail="" buggy_json="null" gold_json="null"
    t0=$(date +%s); started=$(now_utc)
    echo "=== bench.sh validate-oracle: $case_name ($runs run(s) per side) ==="

    docker volume inspect "$(volume_name "$case_name")" &>/dev/null \
        || err="$case_name is not set up. Run: ./bench.sh setup $case_name"

    local buggy_fail=0 buggy_err=0 gold_pass=0 gold_err=0 gold_applied=false have_gold=false
    [ -f "$gold" ] && have_gold=true

    if [ -z "$err" ]; then
        echo "  Buggy worktree (expect FAIL):"
        if BENCH_RESET_NO_BUILD=1 bash "$SELF" reset "$case_name" >"$log_dir/reset-buggy.log" 2>&1; then
            run_series "$case_name" "$runs" buggy "$log_dir" "$tmo"
            buggy_fail=$(count_verdict FAIL); buggy_err=$(count_verdict ERROR)
            buggy_json="{\"expected\": \"FAIL\", \"matched\": $buggy_fail, \"errors\": $buggy_err, \"exit_codes\": $(series_codes_json), \"runs\": $(series_json)}"
        else
            err="reset failed (see $log_dir/reset-buggy.log)"
        fi
    fi

    if [ -z "$err" ] && [ "$have_gold" = true ]; then
        echo "  Gold patch $gold (expect PASS):"
        SER_RC=(); SER_TO=(); SER_DUR=(); SER_SUM=(); SER_LOG=(); SER_VERDICT=()
        local arc=0
        if ! BENCH_RESET_NO_BUILD=1 bash "$SELF" reset "$case_name" >"$log_dir/reset-gold.log" 2>&1; then
            err="reset failed (see $log_dir/reset-gold.log)"
        else
            apply_patch "$case_name" "$gold" "$log_dir/apply-gold.log" || arc=$?
            if [ "$arc" -eq 0 ]; then
                gold_applied=true
                run_series "$case_name" "$runs" gold "$log_dir" "$tmo"
                gold_pass=$(count_verdict PASS); gold_err=$(count_verdict ERROR)
            else
                detail="gold.patch does not apply (see $log_dir/apply-gold.log)"
            fi
        fi
        gold_json="{\"expected\": \"PASS\", \"patch\": $(json_str "cases-solution/$case_name/gold.patch"), \"patch_applied\": $gold_applied,"
        gold_json+=" \"matched\": $gold_pass, \"errors\": $gold_err, \"exit_codes\": $(series_codes_json), \"runs\": $(series_json)}"
    fi

    if [ -z "$err" ]; then
        echo "  Resetting the worktree (and rebuilding the buggy source) ..."
        bash "$SELF" reset "$case_name" >"$log_dir/reset-after.log" 2>&1 \
            || warn "final reset failed (see $log_dir/reset-after.log)"
    fi

    # Status:
    #   ERROR   infrastructure problem (not set up, reset failed, any ERROR run,
    #           or gold.patch does not apply)
    #   NO-GOLD no gold.patch (buggy-side runs are still reported)
    #   SOUND   buggy FAIL in every run and gold PASS in every run
    #   UNSOUND buggy never FAILs, or gold never PASSes (consistently wrong)
    #   FLAKY   anything in between
    if [ -n "$err" ]; then status=ERROR; detail="$err"
    elif [ "$buggy_err" -gt 0 ] || [ "$gold_err" -gt 0 ]; then status=ERROR; detail="oracle reported ERROR in $((buggy_err + gold_err)) run(s)"
    elif [ "$have_gold" = false ]; then status=NO-GOLD; detail="no cases-solution/$case_name/gold.patch"
    elif [ "$gold_applied" = false ]; then status=ERROR
    elif [ "$buggy_fail" -eq "$runs" ] && [ "$gold_pass" -eq "$runs" ]; then status=SOUND
    elif [ "$buggy_fail" -eq 0 ] || [ "$gold_pass" -eq 0 ]; then status=UNSOUND
    else status=FLAKY; fi
    [ -n "$detail" ] || detail="buggy FAIL $buggy_fail/$runs, gold PASS $gold_pass/$runs"

    local out
    out="{\"schema\": \"ddbench.validate-oracle/v1\", \"case\": $(json_str "$case_name"), \"status\": \"$status\","
    out+=" \"runs_per_side\": $runs, \"buggy\": $buggy_json, \"gold\": $gold_json, \"detail\": $(json_str "$detail"),"
    out+=" \"timeout_s\": $tmo, \"log_dir\": $(json_str "$log_dir"), \"duration_s\": $(( $(date +%s) - t0 )),"
    out+=" \"started_at\": \"$started\", \"timestamp\": \"$(now_utc)\"}"
    emit_json "$json" "$out"

    echo "=== validate-oracle $case_name: $status ($detail) ==="
    case "$status" in
        SOUND) exit 0 ;;
        UNSOUND|FLAKY) exit 1 ;;
        NO-GOLD) exit 3 ;;
        *) exit 2 ;;
    esac
}

cmd_eval_all() {
    require_cmd python3
    exec python3 "$REPO_ROOT/harness/eval_all.py" --bench "$SELF" "$@"
}

# ── Main ─────────────────────────────────────────────────────────────────────

usage() {
    cat <<EOF
Usage: bench.sh <command> [args]

Cases:
  list                                 List all cases and whether they are set up
  build-images [project...]            Build (or refresh after a Dockerfile change) project images
  setup <case> [--no-warm]             Build the image, create the case repository (history
                                       truncated at the buggy commit), build it, and warm the
                                       case's dependency cache by running the oracle once online
  reproduce <case>                     Run the case's oracle against the worktree (offline)
  rebuild <case>                       Run the worktree's REBUILD.sh (compile check)
  reset <case>                         Restore the pristine buggy worktree and rebuild it
  info <case> [field]                  Print Docker objects/paths (fields: uid project volume
                                       context_volume deps_volume cache_volume container image
                                       workdir deps_path cpus scoring_network buggy_sha)
  clean <case>                         Remove the case's container and volumes
  clean-all                            Remove ALL bug-bench containers, volumes and images
  legacy-volumes [--remove]            List (or remove) volumes left by older bench.sh layouts

Sessions:
  shell <case> [--addon <name>]...     Interactive human shell (mounts /bench; reuses a
                                       running container)
  agent <case> --addon <name> [opts]   Run an AI agent in an isolated container (no /bench)
  stop <case>                          Stop the case's running container

Evaluation:
  eval <case> --patch FILE [--runs N] [--json OUT|-] [--log-dir DIR] [--timeout SECS] [--no-reset]
      Reset to the buggy commit, git-apply FILE (a unified diff relative to the repository
      root), run the oracle N times (default 1), then reset again. Verdict over the runs:
      any FAIL => FAIL, else any ERROR => ERROR, else PASS. A patch that does not apply
      => FAIL with patch_applied=false. Exit code 0/1/2 = PASS/FAIL/ERROR.
  validate-oracle <case> [--runs N] [--json OUT|-] [--log-dir DIR] [--timeout SECS]
      Buggy worktree must FAIL N times, then cases-solution/<case>/gold.patch must PASS N
      times. Status SOUND (exit 0), UNSOUND or FLAKY (exit 1), ERROR (exit 2), NO-GOLD (exit 3).
  eval-all --predictions FILE.jsonl --out DIR [--jobs J] [--runs N] [--timeout SECS]
           [--setup] [--no-reset]
      Evaluate many predictions in parallel (distinct cases only). Each JSONL line is
      {"case": "<case>", "patch": "<diff text>"} or {"case": ..., "patch_file": "<path>"}.
      Writes DIR/<case>/result.json plus DIR/summary.json and DIR/summary.md (requires python3).

Agent options (agent command; --addon/--context also for shell):
  --addon <name>       Install a tool addon (repeatable). See addons/README.md
  --prompt <text>      Pass a prompt to the agent
  --cmd <command>      Override the agent command to run
  --config <path>      Agent config file (mounted at /configs/agent_config.yaml)
  --output-dir <path>  Host directory for agent output. mini-swe-agent writes
                       trajectory.traj.json there (inside the container: /output, an opaque
                       staging dir under .bench/ copied here when the agent exits)
  --context            Mount the case's context/ folder read-only at ./context
  --force              With --context: recreate an already-running agent container

reproduce exit codes: 0 = PASS (bug fixed), 1 = FAIL (bug present, or the worktree does
not build), 2 = ERROR (not set up / infrastructure / inconclusive).

Inside every container the worktree is $WT_PATH. Docker objects are named by an
opaque per-case id, so agents cannot learn the case name or upstream issue.
Scoring containers run with --network none against the per-case dependency cache
filled by setup; agent containers never see that cache.

Environment:
  BENCH_CPUS=N            Cap CPUs per container (never above a case's num_cpus)
  BENCH_OFFLINE=0         Give scoring containers network access (debugging)
  BENCH_RUN_TIMEOUT=SECS  Default per-run timeout for eval/validate-oracle (default $DEFAULT_RUN_TIMEOUT)
  BENCH_RESET_NO_BUILD=1  Skip the rebuild that 'reset' runs after restoring the source
  BENCH_CONTEXT=1         Same as --context (set by harness/run_agent.sh --context)
  BENCH_HOST_NETWORK=1    Use --network host for agent containers (reach host localhost)
  ANTHROPIC_API_KEY, OPENAI_API_KEY, GEMINI_API_KEY, DEEPSEEK_API_KEY, TOGETHER_API_KEY,
  FIREWORKS_API_KEY, OPENROUTER_API_KEY, ANTHROPIC_BASE_URL, ANTHROPIC_AUTH_TOKEN
                          Forwarded to agent containers when set
  MSWEA_MODEL_NAME        Forwarded to agent containers for mini-swe-agent (required by it)

Examples:
  ./bench.sh setup dragonfly-6856-flushslots-oob
  ./bench.sh reproduce dragonfly-6856-flushslots-oob
  ./bench.sh validate-oracle raft-358-negative-log-range --runs 3
  ./bench.sh eval raft-358-negative-log-range --patch my-fix.diff --json result.json
  ./bench.sh eval-all --predictions preds.jsonl --out results/run1 --jobs 4
  ./bench.sh shell dragonfly-6856-flushslots-oob --addon custom-gdb-dashboard
  ./bench.sh agent dragonfly-6856-flushslots-oob --addon claude-code
  ./bench.sh agent dragonfly-6856-flushslots-oob --addon mini-swe-agent --prompt "Fix the bug"
EOF
}

main() {
    case "${1:-}" in
        ""|help|-h|--help) usage; [ -n "${1:-}" ] || exit 1; exit 0 ;;
    esac
    [ "${1:-}" = "reproduce" ] && DIE_CODE=2
    require_cmd docker
    DOCKER_NCPU=$(docker info --format '{{.NCPU}}' 2>/dev/null) \
        || die "Docker daemon is not running or not accessible. Start it with: sudo systemctl start docker"

    local cmd="$1"; shift
    case "$cmd" in
        list)      cmd_list ;;
        build-images) cmd_build_images "$@" ;;
        setup)     [ -n "${1:-}" ] || die "Usage: bench.sh setup <case-name> [--no-warm]"; cmd_setup "$@" ;;
        reproduce) [ -n "${1:-}" ] || die "Usage: bench.sh reproduce <case-name>"; cmd_reproduce "$1" ;;
        rebuild)   [ -n "${1:-}" ] || die "Usage: bench.sh rebuild <case-name>"; cmd_rebuild "$1" ;;
        shell)     [ -n "${1:-}" ] || die "Usage: bench.sh shell <case-name> [--addon <name>]"; cmd_shell "$@" ;;
        agent)     [ -n "${1:-}" ] || die "Usage: bench.sh agent <case-name> --addon <name>"; cmd_agent "$@" ;;
        stop)      [ -n "${1:-}" ] || die "Usage: bench.sh stop <case-name>"; cmd_stop "$1" ;;
        reset)     [ -n "${1:-}" ] || die "Usage: bench.sh reset <case-name>"; cmd_reset "$1" ;;
        clean)     [ -n "${1:-}" ] || die "Usage: bench.sh clean <case-name>"; cmd_clean "$1" ;;
        clean-all) cmd_clean_all ;;
        info)      [ -n "${1:-}" ] || die "Usage: bench.sh info <case-name> [field]"; cmd_info "$1" "${2:-}" ;;
        legacy-volumes) cmd_legacy_volumes "$@" ;;
        eval)      [ -n "${1:-}" ] && [ "${1#-}" = "$1" ] || die "Usage: bench.sh eval <case-name> --patch <file.diff> [options]"; cmd_eval "$@" ;;
        validate-oracle) [ -n "${1:-}" ] && [ "${1#-}" = "$1" ] || die "Usage: bench.sh validate-oracle <case-name> [options]"; cmd_validate_oracle "$@" ;;
        eval-all)  cmd_eval_all "$@" ;;
        *)         echo "Unknown command: $cmd" >&2; echo "" >&2; usage >&2; exit 1 ;;
    esac
}

# Parsed as one unit and never returns, so editing this file while a command is
# running cannot make bash execute half-read code afterwards.
main "$@"; exit $?
