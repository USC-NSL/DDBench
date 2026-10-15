#!/usr/bin/env python3
"""generate_devcontainers.py — write .devcontainer/<case>/devcontainer.json for every case.

Usage:
    python3 scripts/generate_devcontainers.py [--check]

Each config mirrors what `bench.sh shell <case>` does: the project image built by
`bench.sh setup`, the case's opaque worktree volume at /workspace, its dependency
cache volume at /deps, the case directory read-only at /bench (so
`bash /bench/reproduce.sh` works), SYS_PTRACE plus the case's docker.caps and
seccomp setting, and the same package-manager environment.

--check exits 1 if any file would change (for CI). Standard library only.
"""

from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(Path(__file__).resolve().parent))
from caseyaml import load_case_yaml  # noqa: E402

EXTENSIONS = {
    "dragonfly": ["ms-vscode.cpptools", "ms-vscode.cmake-tools"],
    "kvrocks": ["ms-vscode.cpptools", "ms-vscode.cmake-tools", "golang.go"],
    "rocksdb": ["ms-vscode.cpptools", "ms-vscode.cmake-tools"],
    "consul": ["golang.go"],
    "etcd": ["golang.go"],
    "nats": ["golang.go"],
    "raft": ["golang.go"],
    "bookkeeper": ["vscjava.vscode-java-pack", "vscjava.vscode-maven"],
    "zookeeper": ["vscjava.vscode-java-pack", "vscjava.vscode-maven"],
    "kafka": ["vscjava.vscode-java-pack", "vscjava.vscode-gradle", "scalameta.metals"],
    "raft-rs": ["rust-lang.rust-analyzer"],
    "ra": ["erlang-ls.erlang-ls"],
    "rabbitmq": ["erlang-ls.erlang-ls"],
}

# Same environment bench.sh gives its containers (see "Dependency caches").
DEPS_ENV = {
    "GOMODCACHE": "/deps/go/mod",
    "GOCACHE": "/deps/go/build",
    "CARGO_HOME": "/deps/cargo",
    "GRADLE_USER_HOME": "/deps/gradle",
    "MAVEN_OPTS": "-Dmaven.repo.local=/deps/m2",
}

# CPU limits are only pinned in the devcontainer where the oracle depends on
# them (a small limit is also safe on small machines).
CPU_PIN_MAX = 4


def case_uid(case: str) -> str:
    return hashlib.sha256(case.encode()).hexdigest()[:12]


def render(case: str, meta: dict) -> dict:
    project = meta["project"]
    uid = case_uid(case)
    docker = meta.get("docker") or {}
    run_args = ["--cap-add=SYS_PTRACE"]
    for cap in docker.get("caps") or []:
        if f"--cap-add={cap}" not in run_args:
            run_args.append(f"--cap-add={cap}")
    if str(docker.get("seccomp_unconfined", "")).lower() == "true":
        run_args.append("--security-opt=seccomp=unconfined")
    try:
        cpus = int(docker.get("num_cpus") or 0)
    except ValueError:
        cpus = 0
    if 0 < cpus <= CPU_PIN_MAX:
        run_args.append(f"--cpus={cpus}")

    post = "git config --global --add safe.directory '*'"
    env = {"BENCH_WORKDIR": "/workspace/src", **DEPS_ENV}

    return {
        "name": f"DDBench - {case}",
        "image": f"bug-bench/{project}",
        "runArgs": run_args,
        "mounts": [
            f"source=bug-bench-ws-{uid},target=/workspace,type=volume",
            f"source=bug-bench-deps-{uid},target=/deps,type=volume",
            f"source=${{localWorkspaceFolder}}/cases/{case},target=/bench,type=bind,readonly",
        ],
        "workspaceFolder": "/workspace/src",
        "containerEnv": env,
        "postCreateCommand": post,
        "customizations": {"vscode": {"extensions": EXTENSIONS.get(project, [])}},
    }


def main() -> int:
    check = "--check" in sys.argv[1:]
    cases = sorted(p.parent.name for p in (ROOT / "cases").glob("*/case.yaml"))
    wanted = set()
    stale = []
    for case in cases:
        meta = load_case_yaml(ROOT / "cases" / case / "case.yaml")
        if meta["project"] not in EXTENSIONS:
            print(f"WARNING: no VS Code extensions configured for project {meta['project']}", file=sys.stderr)
        out = ROOT / ".devcontainer" / case / "devcontainer.json"
        wanted.add(case)
        text = json.dumps(render(case, meta), indent=2) + "\n"
        if not out.exists() or out.read_text() != text:
            stale.append(str(out.relative_to(ROOT)))
            if not check:
                out.parent.mkdir(parents=True, exist_ok=True)
                out.write_text(text)
    extra = sorted(p.parent.name for p in (ROOT / ".devcontainer").glob("*/devcontainer.json")
                   if p.parent.name not in wanted)
    for case in extra:
        print(f"WARNING: .devcontainer/{case} has no matching case directory", file=sys.stderr)
    if check:
        if stale:
            print("out of date:\n  " + "\n  ".join(stale))
            return 1
        return 0
    print(f"{len(cases)} devcontainer configs ({len(stale)} written)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
