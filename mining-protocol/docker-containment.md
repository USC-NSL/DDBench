# Docker Containment

Every case is built, run and scored in Docker by `bench.sh`. There is no host mode. This
document explains what the containers guarantee and what that means for case authors.

## Why Docker Self-Containment Matters

The benchmark must produce identical results regardless of when, where, or by whom it is run, and an agent under evaluation must not be able to read the answer out of its environment.

### Reproducibility across time and environments

Bug reproduction depends on exact versions of:
- The project source code (specific commit)
- Build toolchain (compiler version, linker, standard library)
- Third-party dependencies (Go modules, crates, Maven/Gradle artifacts)
- Runtime dependencies (shared libraries, system tools)
- Client tools used to trigger the bug (redis-cli, curl, Go test runner)

Without containment, any of these can drift. A bug that crashes on GCC 12 may silently succeed on GCC 13. A race condition that fires on kernel 5.15 may vanish on 6.8. The benchmark loses its value if results depend on the host.

### What "self-contained" means concretely

A case is self-contained if this succeeds on any machine with Docker, without prior setup or manual configuration:

```bash
./bench.sh setup <case-name> && ./bench.sh reproduce <case-name>
```

This means:
- All build dependencies are declared in the project Dockerfile
- The build command in `case.yaml` works inside the container without modification
- The oracle requires only tools present in the container image
- Network access is needed only during `setup` (image build, clone, online build, warm-up). Scoring runs offline.
- No host-specific paths, environment variables, or kernel features are assumed

---

## Images

```
bug-bench/base-cpp      ubuntu:24.04 (pinned by digest) + build tools, gdb, redis-cli, ...
bug-bench/base-go       ubuntu:24.04 + Go 1.23.6 (from the official image) + delve
  └── bug-bench/<project>   FROM a base image, plus project-specific dependencies
bug-bench/<project>     standalone: FROM a pinned upstream image (Ubuntu with a JDK or
                        Rust toolchain, erlang, elixir) for Java/Scala, Rust and Erlang projects
```

- `docker/<project>.Dockerfile` defines `bug-bench/<project>`; `project` in `case.yaml` selects it.
- Every external base image is pinned by digest.
- Images carry a fingerprint of their Dockerfile (and of the `bug-bench/*` images they build on) and are rebuilt automatically when it changes. `./bench.sh build-images [project...]` builds or refreshes them ahead of time.
- No source code and no build outputs are baked into images: source lives in volumes, builds happen at `setup`.
- Go cases whose `go.mod` asks for a newer toolchain get it through `GOTOOLCHAIN=auto` during setup; it is cached in the case's dependency volume.

---

## Volumes and containment

### Opaque case identity

The case name carries the upstream issue number and a diagnostic slug, so nothing an agent
container can observe may contain it: not the working directory, the environment, the
hostname, or mount sources (`/proc/self/mountinfo` lists volume names and bind-mount host
paths). bench.sh therefore names every per-case Docker object after an opaque uid, the first
12 hex characters of sha256 of the case name, and every container uses the same worktree path,
`/workspace/src`. Absolute paths baked into build outputs (`CMakeCache.txt`,
`compile_commands.json`, Go/Rust/Java artifacts) are identical in every container and carry no
case information.

| Object | Name | Contents |
|--------|------|----------|
| Worktree volume | `bug-bench-ws-<uid>` | `/workspace/src`: the case repository, build outputs, `SYMPTOM.md`, `REBUILD.sh` |
| Dependency volume | `bug-bench-deps-<uid>` | `/deps`: Go module + build cache, Cargo, Gradle, Maven |
| Context volume | `bug-bench-ctx-<uid>` | Copy of `cases/<case>/context/`, staged for `--context` |
| Container | `bug-bench-<uid>` | The case's shell/agent/reproduce container |
| Project cache volume | `bug-bench-<project>-cache` | `/cache/repo.git`: bare full-history clone, shared by the project's cases |
| Tools volume | `bug-bench-tools` | `/opt/tools`: addon installations |

Per-case volumes and containers carry the Docker label `ddbench.case=<case>` (visible only
through the Docker API, never inside a container): `docker ps --filter label=ddbench.case=<case>`.
`./bench.sh info <case> [field]` prints the uid and every object name. bench.sh commands keep
taking the case name; only Docker sees the uid. `./bench.sh legacy-volumes [--remove]` lists or
removes volumes left by older layouts.

### Containment of the upstream fix

An agent must never be able to read commits that come after the buggy commit: they contain
the upstream fix.

1. **Each case gets its own worktree volume.** A sibling case of the same project may sit at a later commit whose ancestry contains this case's fix, so cases never share a filesystem.
2. **Each case repository holds only the ancestry of the buggy commit.** Setup fetches exactly that ancestry from the project cache, deletes every ref, remote, `FETCH_HEAD` and reflog entry, and garbage-collects (submodules too). Descendant objects are never transferred, so `git show <fix-sha>`, `git log --all` and `git diff HEAD..main` have nothing to find.
3. **Containment gate.** Setup asserts zero refs and that the number of commit objects equals the length of the ancestry; if either fails it aborts (`CONTAINMENT FAILURE`) rather than produce a tainted case.
4. **The full-history clone is mounted only at setup** (read-only, to build the case repository) and by `reset`, read-only and in a separate container without the worktree, to resolve `buggy_commit` to a SHA. It is never mounted into agent or reproduce containers.

Consequence for authors: `buggy_commit` must be resolvable in the full clone, and the fix
commit is not in the case repository. To look at the fix (e.g. to derive `gold.patch`), read
it from the project cache volume.

---

## Container mounts

| | setup builds | reproduce | rebuild / reset | shell, devcontainer | agent |
|---|---|---|---|---|---|
| `/workspace/src` (worktree) | rw | rw | rw | rw | rw |
| `/bench` (case dir) | — | ro | — | ro | **never** |
| `/deps` (dependency volume) | rw | rw | rw | rw | **never** (empty, container-local) |
| `/workspace/src/context` | — | — | — | ro, with `--context` | ro, with `--context` |
| Network | online | none | none | online | online |

- Build containers (setup, the build step of reproduce, rebuild, reset) never mount the case directory: a build must never copy oracle files into the agent-visible worktree, and every build runs the same way.
- The setup warm-up is a reproduce run with network access.
- `reproduce` runs the oracle in a fresh container named `bug-bench-<uid>` with the case's capabilities, CPU limit and seccomp setting.
- `shell` is a human session: it mounts `/bench` so that `bash /bench/reproduce.sh` works, mounts the dependency volume, and is never reused for `agent`.

### Agent isolation

`./bench.sh agent <case> --addon <name>` (and `harness/run_agent.sh`) starts a container that:
- never mounts `/bench`: the oracle, case docs, harness files and `context/` sources are invisible;
- never mounts the dependency volume: scoring runs write it (it can hold artifacts compiled from oracle tests and gold patches), so the agent gets the same package-manager environment pointing at an empty container-local `/deps` and downloads what it needs over its own network;
- gets `SYMPTOM.md` (copied at setup, restored by `reset`) in the worktree, and `context/` read-only at `/workspace/src/context` only with `--context`;
- carries no case-specific environment variables, paths or hostnames; its `--output-dir` is staged under an opaque directory and copied out when the agent exits;
- gets no host `~/.claude` (the `claude-code` addon receives only `.credentials.json` and `settings.json`);
- runs the agent as the non-root user `bench`.

A running container that mounts `/bench` (one started by `shell`) is recreated before an agent
uses it. `reset` restores pristine `SYMPTOM.md` and `REBUILD.sh` and removes oracle leftovers
before the next agent run.

---

## Offline scoring and the dependency cache

Package managers are pointed at `/deps`, a per-case volume:

| Variable | Value |
|----------|-------|
| `GOMODCACHE` | `/deps/go/mod` |
| `GOCACHE` | `/deps/go/build` |
| `CARGO_HOME` | `/deps/cargo` |
| `GRADLE_USER_HOME` | `/deps/gradle` |
| `MAVEN_OPTS` | `-Dmaven.repo.local=/deps/m2` |

- **setup** builds online, then runs the oracle once online ("warm-up") so that test-only dependencies are fetched too, and records a stamp in the volume.
- **reproduce, rebuild, reset** build and run **offline**: `--network none`, `GOPROXY=off`, `CARGO_NET_OFFLINE=true`, Gradle offline (an init script in `/deps/gradle`), Maven offline (a `settings.xml` written into the ephemeral container's `~/.m2`). `reproduce` refuses to run if the cache was never warmed (`setup --no-warm`).
- **shell** mounts the volume read-write with network; **agent** never mounts it.

Consequences for authors:
- **The oracle must not download anything at reproduce time.** Whatever it needs must be fetched by `build.command` or by the warm-up run. The warm-up runs on the buggy code, which FAILs: if the PASS path needs something the FAIL path never touched (a later build step, another test module), resolve it up front. `validate-oracle` runs the gold side offline and catches this.
- **Never hard-code cache locations** (`-Dmaven.repo.local=...`, `GOPATH`, `GOMODCACHE`, `CARGO_HOME`, `GRADLE_USER_HOME`) and never pass a custom Maven `-s` settings file: the environment already points everything at `/deps`, and offline mode depends on it.
- **Patches that add new third-party dependencies cannot build at scoring time**, for agents and gold patches alike. Choose gold patches that need none.
- `BENCH_OFFLINE=0` gives scoring containers network access for debugging. A case that cannot work offline may set `docker.offline: false` in `case.yaml`; this is a last resort, since scoring then depends on the network.

---

## CPUs

`docker.num_cpus` sets `--cpus = min(num_cpus, Docker host CPUs)`, capped further by the
`BENCH_CPUS` environment variable (which never raises a case above its `num_cpus`).
`OMP_NUM_THREADS` is set to the same number so `nproc` (and `make -j$(nproc)`) inside the
container reports it. bench.sh warns when a case gets fewer CPUs than it asks for, since
timing-sensitive oracles may behave differently.

## Capabilities and seccomp

Most cases need no extra capabilities. When a case requires elevated permissions (e.g., `NET_ADMIN` for network namespace manipulation), declare them in `case.yaml`:

```yaml
docker:
  caps: ["NET_ADMIN"]
```

`bench.sh` translates this to `--cap-add=NET_ADMIN`. `SYS_PTRACE` is always added (gdb, dlv).
`docker.seccomp_unconfined: true` adds `--security-opt seccomp=unconfined`, for syscalls the
default profile blocks (e.g. io_uring).

Prefer oracles that need no extra capabilities. Process-level faults (`SIGSTOP`, kill, a pausable TCP proxy) need none and target exactly one peer.

---

## Adding Docker Support for a New Project

### If the project's language already has a base image

Create `docker/<project>.Dockerfile`:

```dockerfile
FROM bug-bench/base-cpp
# or: FROM bug-bench/base-go

# Install project-specific build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    <dependency-1> \
    <dependency-2> \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
```

**Rules:**
- Use `--no-install-recommends` to minimize image size
- Clean apt cache (`rm -rf /var/lib/apt/lists/*`) after install
- Do NOT clone source code — it lives in the case volumes
- Do NOT run builds or pre-fetch project dependencies — builds happen at `bench.sh setup`, and dependencies belong in the per-case `/deps` volume
- Keep the Dockerfile minimal — only what's needed to compile and run
- Install every tool the oracle uses (client CLIs, `timeout`, `python3`, ...); the oracle cannot install anything at reproduce time

Build and inspect it with `./bench.sh build-images <project>` (base images are built first)
and `docker run --rm -it bug-bench/<project> bash`.

### If the project uses a new language

1. Either create `docker/base-<language>.Dockerfile` following the pattern of `base-cpp` or `base-go`, or write a standalone project Dockerfile `FROM` a pinned upstream language image (as the Java, Rust and Erlang projects do)
2. Include the language toolchain, debugger, and standard utilities
3. Pin the toolchain version explicitly, and pin every external base image by digest
4. Make sure the toolchain's caches can be redirected to `/deps` through the variables above (or extend bench.sh's dependency handling for the new package manager)
