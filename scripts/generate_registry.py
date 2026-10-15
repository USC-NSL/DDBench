#!/usr/bin/env python3
"""generate_registry.py — regenerate registry/case_registry.json from cases/*/case.yaml.

Usage:
    python3 scripts/generate_registry.py [--resolve] [--check]

Fields taken from case.yaml (always regenerated):
    project, repo, buggy_commit_ref (the case.yaml expression, e.g. "<sha>~1"),
    fix_commit, fix_commit_note, submodules, build, docker, resolve_time
Derived fields:
    buggy_commit   the buggy revision as a full SHA. Kept from the previous
                   registry while buggy_commit_ref is unchanged; --resolve
                   (re)resolves every case through `bench.sh info <case> buggy_sha`
                   (needs Docker and a completed setup of each project).
    language       from the project
    has_solution   cases-solution/<case>/solution.md exists
    gold_complete  cases-solution/<case>/gold.patch exists
    oracle_status  status from registry/oracle_validation.json, if present
Curated fields kept from the previous registry (edit them there):
    oracle_type, system_family, github_url, description, surface_membership,
    contamination_tier, bug_family

--check exits 1 when the registry is out of date (ignores generated_at).
Standard library only.
"""

from __future__ import annotations

import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REGISTRY = ROOT / "registry" / "case_registry.json"
VALIDATION = ROOT / "registry" / "oracle_validation.json"
RESOLVE_TIMES = ROOT / "registry" / "resolve_times.json"
sys.path.insert(0, str(Path(__file__).resolve().parent))
from caseyaml import load_case_yaml  # noqa: E402

LANGUAGE = {
    "bookkeeper": "Java", "consul": "Go", "dragonfly": "C++", "etcd": "Go",
    "kafka": "Java", "kvrocks": "C++", "nats": "Go", "ra": "Erlang",
    "rabbitmq": "Erlang", "raft": "Go", "raft-rs": "Rust", "rocksdb": "C++",
    "zookeeper": "Java",
}
CURATED = ("oracle_type", "system_family", "github_url", "description",
           "surface_membership", "contamination_tier", "bug_family")


def resolve_sha(case: str) -> str | None:
    r = subprocess.run(["bash", str(ROOT / "bench.sh"), "info", case, "buggy_sha"],
                       capture_output=True, text=True)
    sha = r.stdout.strip().splitlines()[-1] if r.returncode == 0 and r.stdout.strip() else ""
    return sha if len(sha) == 40 else None


def main() -> int:
    resolve = "--resolve" in sys.argv[1:]
    check = "--check" in sys.argv[1:]
    old = json.loads(REGISTRY.read_text()) if REGISTRY.exists() else {"cases": []}
    previous = {c["case_id"]: c for c in old.get("cases", [])}
    validation = {}
    if VALIDATION.exists():
        validation = {c["case"]: c for c in json.loads(VALIDATION.read_text()).get("cases", [])}

    # Fallback for a case.yaml without fix_commit: the confirmed fix commit
    # recorded in registry/resolve_times.json.
    confirmed = {}
    if RESOLVE_TIMES.exists():
        confirmed = {c["case_id"]: c.get("fix_commit_sha")
                     for c in json.loads(RESOLVE_TIMES.read_text()).get("cases", [])}

    entries, problems = [], []
    for yaml_path in sorted((ROOT / "cases").glob("*/case.yaml")):
        case = yaml_path.parent.name
        meta = load_case_yaml(yaml_path)
        prev = previous.get(case, {})
        if meta.get("name") != case:
            problems.append(f"{case}: case.yaml name is {meta.get('name')!r}")
        ref = str(meta.get("buggy_commit") or "")
        sha = None
        if resolve:
            sha = resolve_sha(case)
            if sha is None:
                problems.append(f"{case}: could not resolve {ref} (run ./bench.sh setup {case})")
        if sha is None:
            prev_ref = prev.get("buggy_commit_ref")
            prev_sha = prev.get("buggy_commit")
            if prev_ref == ref or (prev_ref is None and prev_sha and ref.startswith(prev_sha)):
                sha = prev_sha
            elif len(ref) == 40 and all(c in "0123456789abcdef" for c in ref):
                sha = ref
            else:
                sha = prev_sha
                problems.append(f"{case}: buggy_commit changed to {ref}; re-run with --resolve")
        docker = dict(meta.get("docker") or {})
        entry = {
            "case_id": case,
            "project": meta.get("project"),
            "repo": meta.get("repo"),
            "buggy_commit": sha,
            "buggy_commit_ref": ref,
            "fix_commit": meta.get("fix_commit"),
        }
        if "fix_commit" not in meta:
            entry["fix_commit"] = confirmed.get(case)
            problems.append(f"{case}: case.yaml has no fix_commit; using registry/resolve_times.json")
        if meta.get("fix_commit_note"):
            entry["fix_commit_note"] = meta["fix_commit_note"]
        entry.update({
            "language": LANGUAGE.get(meta.get("project"), prev.get("language")),
            "build": dict(meta.get("build") or {}),
            "docker": docker,
            "submodules": bool(meta.get("submodules")),
        })
        for k in CURATED:
            if k in prev:
                entry[k] = prev[k]
        entry["has_solution"] = (ROOT / "cases-solution" / case / "solution.md").exists()
        entry["gold_complete"] = (ROOT / "cases-solution" / case / "gold.patch").exists()
        if case in validation:
            entry["oracle_status"] = validation[case].get("status")
        if meta.get("resolve_time"):
            entry["resolve_time"] = meta["resolve_time"]
        elif prev.get("resolve_time"):
            entry["resolve_time"] = prev["resolve_time"]
        entries.append(entry)

    new = {
        "version": "2.0.0",
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "generator": "scripts/generate_registry.py",
        "total_cases": len(entries),
        "cases": entries,
    }
    for p in problems:
        print(f"WARNING: {p}", file=sys.stderr)
    if check:
        strip = lambda d: {k: v for k, v in d.items() if k != "generated_at"}  # noqa: E731
        if strip(old) != strip(new):
            print("registry/case_registry.json is out of date; run scripts/generate_registry.py")
            return 1
        return 0
    REGISTRY.write_text(json.dumps(new, indent=2) + "\n")
    print(f"wrote {REGISTRY.relative_to(ROOT)}: {len(entries)} cases "
          f"({sum(e['gold_complete'] for e in entries)} with gold.patch)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
