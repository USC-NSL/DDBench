#!/usr/bin/env python3
"""Compute shape and basic metrics of the ddbench-cases benchmark.

Reads ../registry/case_registry.json and the per-case directories under ../cases/
(and ../cases-solution/), emitting aggregate statistics useful for describing the
dataset in a paper. Writes JSON + Markdown summaries next to this script.

Usage:
    python3 benchmark_stats.py           # writes benchmark_stats.{json,md}
    python3 benchmark_stats.py --stdout  # also prints Markdown to stdout
"""

from __future__ import annotations

import argparse
import json
import statistics
from collections import Counter
from pathlib import Path
from urllib.parse import urlparse

from bug_categories import (
    CATEGORY_DESCRIPTIONS,
    CATEGORY_ORDER,
    FAMILY_TO_CATEGORY,
)


SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
REGISTRY = REPO_ROOT / "registry" / "case_registry.json"
CASES_DIR = REPO_ROOT / "cases"
SOLUTIONS_DIR = REPO_ROOT / "cases-solution"

TIER_FILES = {
    "tier1": REPO_ROOT / "registry" / "tier1_membership.json",
    "tier2": REPO_ROOT / "registry" / "tier2_membership.json",
    "tier3": REPO_ROOT / "registry" / "tier3_membership.json",
}


def count_lines(path: Path) -> int | None:
    if not path.is_file():
        return None
    with path.open("rb") as f:
        return sum(1 for _ in f)


def dir_file_count(path: Path) -> int:
    if not path.is_dir():
        return 0
    return sum(1 for p in path.rglob("*") if p.is_file())


def classify_url(url: str) -> str:
    if not url:
        return "unknown"
    parsed = urlparse(url)
    host = parsed.netloc
    if "jira" in host or "/jira/" in parsed.path:
        return "jira"
    if "github.com" in host:
        if "/pull/" in url:
            return "github-pr"
        if "/issues/" in url:
            return "github-issue"
        return "github-other"
    return "other"


def summarize_numeric(values: list[int]) -> dict:
    values = [v for v in values if v is not None]
    if not values:
        return {"n": 0}
    return {
        "n": len(values),
        "min": min(values),
        "max": max(values),
        "mean": round(statistics.mean(values), 2),
        "median": statistics.median(values),
        "p25": round(statistics.quantiles(values, n=4)[0], 2) if len(values) >= 4 else None,
        "p75": round(statistics.quantiles(values, n=4)[2], 2) if len(values) >= 4 else None,
        "total": sum(values),
    }



def load_tier_membership() -> dict[str, str]:
    case_to_tier: dict[str, str] = {}
    for tier, path in TIER_FILES.items():
        if not path.is_file():
            continue
        data = json.loads(path.read_text())
        for entry in data.get("cases", []):
            case_id = entry.get("corpus_case") or entry.get("case_id")
            if case_id:
                case_to_tier[case_id] = tier
    return case_to_tier


def build_stats() -> dict:
    registry = json.loads(REGISTRY.read_text())
    cases = registry["cases"]
    tier_map = load_tier_membership()

    per_case_metrics = []
    for c in cases:
        case_dir = CASES_DIR / c["case_id"]
        sol_dir = SOLUTIONS_DIR / c["case_id"]
        per_case_metrics.append(
            {
                "case_id": c["case_id"],
                "symptom_lines": count_lines(case_dir / "symptom.md"),
                "reproduce_md_lines": count_lines(case_dir / "reproduce.md"),
                "verification_lines": count_lines(case_dir / "verification.md"),
                "readme_lines": count_lines(case_dir / "README.md"),
                "reproduce_sh_lines": count_lines(case_dir / "reproduce.sh"),
                "setup_sh_lines": count_lines(case_dir / "setup.sh"),
                "context_files": dir_file_count(case_dir / "context"),
                "inject_test_files": dir_file_count(case_dir / "inject_test"),
                "solution_lines": count_lines(sol_dir / "solution.md"),
                "has_context": (case_dir / "context").is_dir(),
                "has_inject_test": (case_dir / "inject_test").is_dir(),
            }
        )

    pcm = {m["case_id"]: m for m in per_case_metrics}

    def counter(field: str) -> dict:
        return dict(Counter(c.get(field) for c in cases).most_common())

    url_kinds = Counter(classify_url(c.get("github_url", "")) for c in cases)

    # 5-way collapse of raw bug_family labels
    unmapped = sorted({c["bug_family"] for c in cases if c["bug_family"] not in FAMILY_TO_CATEGORY})
    cat_counts = Counter(
        FAMILY_TO_CATEGORY.get(c["bug_family"], "uncategorized") for c in cases
    )
    by_bug_category = {name: cat_counts.get(name, 0) for name in CATEGORY_ORDER}
    if cat_counts.get("uncategorized"):
        by_bug_category["uncategorized"] = cat_counts["uncategorized"]

    # tier cross checks
    tier_from_registry = Counter(c.get("surface_membership") for c in cases)
    tier_from_membership = Counter(tier_map.get(c["case_id"], "unassigned") for c in cases)

    stats = {
        "generated_from": str(REGISTRY.relative_to(REPO_ROOT)),
        "registry_version": registry.get("version"),
        "registry_generated_at": registry.get("generated_at"),
        "totals": {
            "cases": len(cases),
            "projects": len({c["project"] for c in cases}),
            "languages": len({c["language"] for c in cases}),
            "system_families": len({c["system_family"] for c in cases}),
            "bug_families_raw": len({c["bug_family"] for c in cases}),
            "bug_categories": len([n for n in CATEGORY_ORDER if by_bug_category.get(n)]),
            "oracle_types": len({c["oracle_type"] for c in cases}),
            "cases_with_solution": sum(1 for c in cases if c.get("has_solution")),
            "cases_with_gold_complete": sum(1 for c in cases if c.get("gold_complete")),
            "cases_with_context_dir": sum(1 for m in per_case_metrics if m["has_context"]),
            "cases_with_inject_test": sum(1 for m in per_case_metrics if m["has_inject_test"]),
            "cases_with_submodules": sum(1 for c in cases if c.get("submodules")),
        },
        "distributions": {
            "by_project": counter("project"),
            "by_language": counter("language"),
            "by_system_family": counter("system_family"),
            "by_bug_category": by_bug_category,
            "bug_category_descriptions": CATEGORY_DESCRIPTIONS,
            "by_bug_family_raw": counter("bug_family"),
            "bug_family_to_category": FAMILY_TO_CATEGORY,
            "unmapped_bug_families": unmapped,
            "by_oracle_type": counter("oracle_type"),
            "by_surface_tier_registry": dict(tier_from_registry.most_common()),
            "by_surface_tier_membership": dict(tier_from_membership.most_common()),
            "by_contamination_tier": counter("contamination_tier"),
            "by_source_url_kind": dict(url_kinds.most_common()),
        },
        "size_metrics": {
            "symptom_md_lines": summarize_numeric([m["symptom_lines"] for m in per_case_metrics]),
            "reproduce_md_lines": summarize_numeric([m["reproduce_md_lines"] for m in per_case_metrics]),
            "verification_md_lines": summarize_numeric([m["verification_lines"] for m in per_case_metrics]),
            "readme_md_lines": summarize_numeric([m["readme_lines"] for m in per_case_metrics]),
            "reproduce_sh_lines": summarize_numeric([m["reproduce_sh_lines"] for m in per_case_metrics]),
            "setup_sh_lines": summarize_numeric([m["setup_sh_lines"] for m in per_case_metrics]),
            "solution_md_lines": summarize_numeric([m["solution_lines"] for m in per_case_metrics]),
            "context_files_per_case": summarize_numeric([m["context_files"] for m in per_case_metrics]),
            "inject_test_files_per_case": summarize_numeric([m["inject_test_files"] for m in per_case_metrics]),
        },
        "cross_tier_by_language": _cross(cases, "surface_membership", "language"),
        "cross_oracle_by_language": _cross(cases, "oracle_type", "language"),
        "cross_bug_category_by_system_family": _cross_with_map(
            cases, "bug_family", "system_family", row_map=FAMILY_TO_CATEGORY,
            row_order=CATEGORY_ORDER,
        ),
        "per_case_metrics": per_case_metrics,
    }
    return stats


def _cross(cases: list[dict], a: str, b: str) -> dict:
    out: dict[str, dict[str, int]] = {}
    for c in cases:
        out.setdefault(c.get(a, "?"), {}).setdefault(c.get(b, "?"), 0)
        out[c.get(a, "?")][c.get(b, "?")] += 1
    return out


def _cross_with_map(
    cases: list[dict],
    a: str,
    b: str,
    row_map: dict[str, str],
    row_order: list[str] | None = None,
) -> dict:
    out: dict[str, dict[str, int]] = {}
    for c in cases:
        row_key = row_map.get(c.get(a, ""), "uncategorized")
        col_key = c.get(b, "?")
        out.setdefault(row_key, {}).setdefault(col_key, 0)
        out[row_key][col_key] += 1
    if row_order:
        ordered = {k: out[k] for k in row_order if k in out}
        for k, v in out.items():
            if k not in ordered:
                ordered[k] = v
        out = ordered
    return out


def to_markdown(stats: dict) -> str:
    lines: list[str] = []
    lines.append("# Benchmark Shape and Basic Metrics")
    lines.append("")
    lines.append(f"Source: `{stats['generated_from']}` "
                 f"(version {stats['registry_version']}, "
                 f"generated {stats['registry_generated_at']}).")
    lines.append("")

    lines.append("## Totals")
    lines.append("")
    lines.append("| Metric | Value |")
    lines.append("|---|---|")
    for k, v in stats["totals"].items():
        lines.append(f"| {k.replace('_', ' ')} | {v} |")
    lines.append("")

    for title, key in [
        ("Projects", "by_project"),
        ("Languages", "by_language"),
        ("System families", "by_system_family"),
        ("Oracle types", "by_oracle_type"),
        ("Surface tier (registry field)", "by_surface_tier_registry"),
        ("Surface tier (membership files)", "by_surface_tier_membership"),
        ("Contamination tier", "by_contamination_tier"),
        ("Source URL kind", "by_source_url_kind"),
    ]:
        dist = stats["distributions"][key]
        total = sum(dist.values()) or 1
        lines.append(f"## Distribution: {title}")
        lines.append("")
        lines.append("| Bucket | Count | Share |")
        lines.append("|---|---:|---:|")
        for bucket, count in dist.items():
            lines.append(f"| {bucket} | {count} | {count/total:.1%} |")
        lines.append("")

    # Bug categories — headline 5-way collapse with descriptions
    cats = stats["distributions"]["by_bug_category"]
    descs = stats["distributions"]["bug_category_descriptions"]
    total = sum(cats.values()) or 1
    lines.append("## Distribution: Bug categories (5-way)")
    lines.append("")
    lines.append("| Category | Count | Share | Description |")
    lines.append("|---|---:|---:|---|")
    for name, count in cats.items():
        desc = descs.get(name, "").replace("\n", " ")
        lines.append(f"| {name} | {count} | {count/total:.1%} | {desc} |")
    lines.append("")

    # Raw bug_family labels (fine-grained, from the registry)
    raw = stats["distributions"]["by_bug_family_raw"]
    f2c = stats["distributions"]["bug_family_to_category"]
    total = sum(raw.values()) or 1
    lines.append("## Distribution: Raw bug_family labels (fine-grained)")
    lines.append("")
    lines.append("| Raw label | Count | Share | Rolled up into |")
    lines.append("|---|---:|---:|---|")
    for label, count in raw.items():
        lines.append(
            f"| {label} | {count} | {count/total:.1%} | "
            f"{f2c.get(label, 'uncategorized')} |"
        )
    lines.append("")
    if stats["distributions"].get("unmapped_bug_families"):
        lines.append(
            "> **Note**: unmapped labels found in registry: "
            + ", ".join(stats["distributions"]["unmapped_bug_families"])
        )
        lines.append("")

    lines.append("## Size metrics (per case)")
    lines.append("")
    lines.append("| Artifact | n | min | p25 | median | mean | p75 | max | total |")
    lines.append("|---|---:|---:|---:|---:|---:|---:|---:|---:|")
    for k, s in stats["size_metrics"].items():
        if s.get("n") == 0:
            lines.append(f"| {k} | 0 | - | - | - | - | - | - | - |")
            continue
        lines.append(
            f"| {k} | {s['n']} | {s['min']} | {s.get('p25', '-')} | {s['median']} | "
            f"{s['mean']} | {s.get('p75', '-')} | {s['max']} | {s['total']} |"
        )
    lines.append("")

    lines.append("## Cross-tab: surface tier × language")
    lines.append("")
    lines.append(_render_cross(stats["cross_tier_by_language"]))
    lines.append("")

    lines.append("## Cross-tab: oracle type × language")
    lines.append("")
    lines.append(_render_cross(stats["cross_oracle_by_language"]))
    lines.append("")

    lines.append("## Cross-tab: bug category × system family")
    lines.append("")
    lines.append(_render_cross(stats["cross_bug_category_by_system_family"]))
    lines.append("")
    return "\n".join(lines)


def _render_cross(table: dict[str, dict[str, int]]) -> str:
    col_keys = sorted({k for row in table.values() for k in row})
    header = "| | " + " | ".join(col_keys) + " | total |"
    sep = "|---|" + "|".join(["---:"] * (len(col_keys) + 1)) + "|"
    rows = [header, sep]
    for row_key in table:
        row = table[row_key]
        vals = [str(row.get(c, 0)) for c in col_keys]
        rows.append(f"| {row_key} | " + " | ".join(vals) + f" | {sum(row.values())} |")
    # column totals
    col_totals = [sum(table[r].get(c, 0) for r in table) for c in col_keys]
    rows.append("| **total** | " + " | ".join(str(x) for x in col_totals) + f" | {sum(col_totals)} |")
    return "\n".join(rows)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--stdout", action="store_true", help="also print Markdown to stdout")
    ap.add_argument(
        "--out-dir",
        default=str(SCRIPT_DIR),
        help="directory to write benchmark_stats.{json,md} (default: script dir)",
    )
    args = ap.parse_args()

    stats = build_stats()
    out_dir = Path(args.out_dir).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    json_path = out_dir / "benchmark_stats.json"
    md_path = out_dir / "benchmark_stats.md"
    json_path.write_text(json.dumps(stats, indent=2))
    md = to_markdown(stats)
    md_path.write_text(md)

    print(f"wrote {json_path}")
    print(f"wrote {md_path}")
    if args.stdout:
        print()
        print(md)


if __name__ == "__main__":
    main()
