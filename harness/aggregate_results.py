#!/usr/bin/env python3
"""aggregate_results.py — Aggregate per-case result JSONs into summary statistics.

Usage:
    python3 harness/aggregate_results.py <results-dir> [registry-json]

Reads:
    <results-dir>/<case-name>/result.json  — written by harness/score_case.sh
        ("result": PASS|FAIL|ERROR) or by `bench.sh eval` / eval-all
        ("verdict": PASS|FAIL|ERROR)
    registry-json (default: registry/case_registry.json next to this harness)
        — used to stratify by bug family, project and exposure tier

Outputs:
    <results-dir>/summary.json  — machine-readable aggregate
    <results-dir>/summary.md    — human-readable markdown report

Verdicts: PASS = fixed, FAIL = not fixed (a model failure), ERROR = the oracle
or the infrastructure could not produce a verdict. ERROR results are reported
separately and are NOT counted as failures: pass_rate = passed / (passed +
failed). pass_rate_all = passed / total treats ERROR as not passed.
"""

from __future__ import annotations

import json
import os
import sys
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path


VERDICTS = ("PASS", "FAIL", "ERROR")


def normalize(r: dict) -> dict:
    """Map score_case.sh and bench.sh eval result files onto one shape."""
    verdict = r.get("result") or r.get("verdict") or "ERROR"
    if verdict not in VERDICTS:
        verdict = "ERROR"
    r["result"] = verdict
    if "duration_seconds" not in r and "duration_s" in r:
        r["duration_seconds"] = r["duration_s"]
    if verdict == "FAIL" and not r.get("failure_reason"):
        if r.get("patch_applied") is False:
            r["failure_reason"] = "patch_does_not_apply"
        elif any(run.get("timed_out") for run in r.get("runs") or []):
            r["failure_reason"] = "timeout"
    if verdict == "ERROR" and not r.get("failure_reason"):
        r["failure_reason"] = "oracle_or_infrastructure_error"
    return r


def load_results(results_dir: str) -> list[dict]:
    """Load all <case>/result.json files from subdirectories."""
    results = []
    results_path = Path(results_dir)
    for case_dir in sorted(results_path.iterdir()):
        result_file = case_dir / "result.json"
        if case_dir.is_dir() and result_file.exists():
            try:
                with open(result_file) as f:
                    data = json.load(f)
            except (OSError, ValueError) as e:
                print(f"WARNING: skipping unreadable {result_file}: {e}", file=sys.stderr)
                continue
            data.setdefault("case", case_dir.name)
            results.append(normalize(data))
    return results


def load_registry(registry_path: str | None) -> dict[str, dict]:
    """Load case registry and index by case_id (empty if unavailable)."""
    if not registry_path or not os.path.exists(registry_path):
        return {}
    with open(registry_path) as f:
        reg = json.load(f)
    return {c["case_id"]: c for c in reg["cases"]}


def counts(results: list[dict]) -> dict:
    """PASS/FAIL/ERROR counts and pass rates for a list of results."""
    total = len(results)
    passed = sum(1 for r in results if r["result"] == "PASS")
    failed = sum(1 for r in results if r["result"] == "FAIL")
    errors = total - passed - failed
    scored = passed + failed
    return {
        "total": total,
        "passed": passed,
        "failed": failed,
        "errors": errors,
        "scored": scored,
        "pass_rate": round(passed / scored, 4) if scored else 0.0,
        "pass_rate_all": round(passed / total, 4) if total else 0.0,
    }


def compute_pass_rate(results: list[dict]) -> dict:
    """Compute overall pass rate (ERROR excluded from the denominator)."""
    return counts(results)


def stratify_by(results: list[dict], registry: dict[str, dict], field: str) -> dict:
    """Stratify pass rate by a registry field (bug_family, project, contamination_tier)."""
    buckets = defaultdict(list)
    for r in results:
        case_id = r["case"]
        meta = registry.get(case_id, {})
        key = meta.get(field, "unknown")
        buckets[key].append(r)

    return {key: counts(buckets[key]) for key in sorted(buckets.keys())}


def compute_patch_stats(results: list[dict]) -> dict:
    """Compute patch metadata statistics for passing vs failing cases."""
    pass_patches = []
    fail_patches = []
    for r in results:
        meta = r.get("patch_metadata", {})
        if not meta or meta.get("files_changed", 0) == 0:
            continue
        entry = {
            "files_changed": meta.get("files_changed", 0),
            "lines_added": meta.get("lines_added", 0),
            "lines_removed": meta.get("lines_removed", 0),
        }
        if r["result"] == "PASS":
            pass_patches.append(entry)
        elif r["result"] == "FAIL":
            fail_patches.append(entry)

    def avg_stats(patches):
        if not patches:
            return {"count": 0, "avg_files": 0, "avg_lines_added": 0, "avg_lines_removed": 0}
        n = len(patches)
        return {
            "count": n,
            "avg_files": round(sum(p["files_changed"] for p in patches) / n, 1),
            "avg_lines_added": round(sum(p["lines_added"] for p in patches) / n, 1),
            "avg_lines_removed": round(sum(p["lines_removed"] for p in patches) / n, 1),
        }

    return {
        "passing_fixes": avg_stats(pass_patches),
        "failing_attempts": avg_stats(fail_patches),
    }


def compute_failure_reasons(results: list[dict], verdict: str = "FAIL") -> dict:
    """Count failure reasons among results with the given verdict."""
    reasons = defaultdict(int)
    for r in results:
        if r["result"] == verdict:
            reason = r.get("failure_reason") or "unknown"
            reasons[reason] += 1
    return dict(sorted(reasons.items(), key=lambda x: -x[1]))


def compute_trajectory_stats(results: list[dict]) -> dict:
    """Compute aggregate trajectory metrics (timing, cost, tokens, behavior).

    Robust: tolerates missing or partial trajectory fields per case.
    """
    cases_with_traj = [r for r in results if r.get("steps_used") is not None]
    if not cases_with_traj:
        return {}

    n = len(cases_with_traj)

    def _safe_int(val, default=0):
        try:
            return int(val) if val is not None else default
        except (ValueError, TypeError):
            return default

    def _safe_float(val, default=0.0):
        try:
            return float(val) if val is not None else default
        except (ValueError, TypeError):
            return default

    # Steps
    steps = [_safe_int(r.get("steps_used")) for r in cases_with_traj]

    # Cost — skip cases where cost is missing
    costs = [_safe_float(r.get("cost")) for r in cases_with_traj if r.get("cost") is not None]

    # Tokens — safely access nested fields
    token_totals = []
    input_totals = []
    output_totals = []
    for r in cases_with_traj:
        tokens = r.get("tokens") or {}
        if isinstance(tokens, dict):
            tt = tokens.get("total_tokens")
            it = tokens.get("total_input_tokens")
            ot = tokens.get("total_output_tokens")
            if tt is not None:
                token_totals.append(_safe_int(tt))
            if it is not None:
                input_totals.append(_safe_int(it))
            if ot is not None:
                output_totals.append(_safe_int(ot))

    # Timing — safely access nested fields
    inference_times = []
    execution_times = []
    for r in cases_with_traj:
        timing = r.get("timing") or {}
        if isinstance(timing, dict):
            inf_t = timing.get("total_inference_time_s")
            if inf_t is not None:
                inference_times.append(_safe_float(inf_t))
            exec_t = timing.get("total_execution_time_s")
            if exec_t is not None:
                execution_times.append(_safe_float(exec_t))

    # Behavior aggregation — safely access nested fields
    total_builds = 0
    total_build_failures = 0
    total_edits = 0
    agg_actions: dict[str, int] = {}
    for r in cases_with_traj:
        behavior = r.get("behavior") or {}
        if isinstance(behavior, dict):
            total_builds += _safe_int(behavior.get("build_attempts"))
            total_build_failures += _safe_int(behavior.get("build_failures"))
            total_edits += _safe_int(behavior.get("edit_count"))
            actions = behavior.get("action_distribution") or {}
            if isinstance(actions, dict):
                for action, count in actions.items():
                    agg_actions[action] = agg_actions.get(action, 0) + _safe_int(count)

    def _safe_avg(lst):
        return round(sum(lst) / len(lst), 3) if lst else None

    return {
        "cases_with_trajectory": n,
        "steps": {
            "total": sum(steps),
            "avg": _safe_avg(steps),
            "min": min(steps) if steps else None,
            "max": max(steps) if steps else None,
        },
        "cost": {
            "total": round(sum(costs), 6) if costs else None,
            "avg": round(sum(costs) / len(costs), 6) if costs else None,
        },
        "tokens": {
            "total": sum(token_totals) if token_totals else None,
            "avg_input": round(sum(input_totals) / len(input_totals)) if input_totals else None,
            "avg_output": round(sum(output_totals) / len(output_totals)) if output_totals else None,
        },
        "timing": {
            "avg_inference_time_s": _safe_avg(inference_times),
            "avg_execution_time_s": _safe_avg(execution_times),
        },
        "behavior": {
            "action_distribution": dict(sorted(agg_actions.items(), key=lambda x: -x[1])),
            "total_build_attempts": total_builds,
            "total_build_failures": total_build_failures,
            "total_edits": total_edits,
        },
    }


def generate_summary_json(results, registry, results_dir):
    """Generate the machine-readable summary."""
    overall = compute_pass_rate(results)

    summary = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "results_dir": str(results_dir),
        "overall": overall,
        "by_bug_family": stratify_by(results, registry, "bug_family"),
        "by_project": stratify_by(results, registry, "project"),
        "by_exposure_tier": stratify_by(results, registry, "contamination_tier"),
        "patch_statistics": compute_patch_stats(results),
        "failure_reasons": compute_failure_reasons(results),
        "error_reasons": compute_failure_reasons(results, "ERROR"),
        "errored_cases": [r["case"] for r in results if r["result"] == "ERROR"],
        "trajectory_statistics": compute_trajectory_stats(results),
        "cases": [
            {
                "case": r["case"],
                "result": r["result"],
                "duration_seconds": r.get("duration_seconds", 0),
                "failure_reason": r.get("failure_reason", ""),
                "summary": r.get("summary") or (r.get("error") or ""),
                "steps_used": r.get("steps_used"),
                "cost": r.get("cost"),
                "tokens": r.get("tokens", {}).get("total_tokens"),
            }
            for r in results
        ],
    }

    output_path = os.path.join(results_dir, "summary.json")
    with open(output_path, "w") as f:
        json.dump(summary, f, indent=2)
    return summary


def generate_summary_md(summary, results_dir):
    """Generate the human-readable markdown report."""
    overall = summary["overall"]
    lines = [
        f"# Scoring Summary",
        f"",
        f"**Generated:** {summary['generated_at']}",
        f"**Results:** {summary['results_dir']}",
        f"",
        f"## Overall",
        f"",
        f"| Metric | Value |",
        f"|--------|-------|",
        f"| Total cases | {overall['total']} |",
        f"| Passed | {overall['passed']} |",
        f"| Failed | {overall['failed']} |",
        f"| Errors (no verdict; not model failures) | {overall['errors']} |",
        f"| **Pass rate** (passed / (passed + failed)) | **{overall['pass_rate']*100:.1f}%** |",
        f"| Pass rate over all cases (ERROR = not passed) | {overall['pass_rate_all']*100:.1f}% |",
        f"",
    ]

    errored = summary.get("errored_cases", [])
    if errored:
        lines.extend([
            "## Errors",
            "",
            "These cases produced no verdict (oracle or infrastructure ERROR). Re-run them;",
            "they are excluded from the failure counts and from the pass rate.",
            "",
        ])
        for case in errored:
            lines.append(f"- `{case}`")
        lines.append("")

    # Failure reasons
    reasons = summary.get("failure_reasons", {})
    if reasons:
        lines.extend([
            "## Failure Breakdown",
            "",
            "| Reason | Count |",
            "|--------|-------|",
        ])
        for reason, count in reasons.items():
            lines.append(f"| {reason} | {count} |")
        lines.append("")

    # Bug family stratification
    by_family = summary.get("by_bug_family", {})
    if by_family:
        lines.extend([
            "## By Bug Family",
            "",
            "| Bug Family | Total | Passed | Failed | Errors | Pass Rate |",
            "|------------|-------|--------|--------|--------|-----------|",
        ])
        for family, stats in sorted(by_family.items(), key=lambda x: x[1]["pass_rate"]):
            pr = f"{stats['pass_rate']*100:.0f}%"
            lines.append(f"| {family} | {stats['total']} | {stats['passed']} | {stats['failed']} | {stats['errors']} | {pr} |")
        lines.append("")

    # Project stratification
    by_project = summary.get("by_project", {})
    if by_project:
        lines.extend([
            "## By Project",
            "",
            "| Project | Total | Passed | Failed | Errors | Pass Rate |",
            "|---------|-------|--------|--------|--------|-----------|",
        ])
        for proj, stats in sorted(by_project.items(), key=lambda x: x[1]["pass_rate"]):
            pr = f"{stats['pass_rate']*100:.0f}%"
            lines.append(f"| {proj} | {stats['total']} | {stats['passed']} | {stats['failed']} | {stats['errors']} | {pr} |")
        lines.append("")

    # Exposure tier stratification
    by_tier = summary.get("by_exposure_tier", {})
    if by_tier:
        lines.extend([
            "## By Exposure Tier",
            "",
            "| Tier | Total | Passed | Failed | Errors | Pass Rate |",
            "|------|-------|--------|--------|--------|-----------|",
        ])
        for tier, stats in sorted(by_tier.items()):
            pr = f"{stats['pass_rate']*100:.0f}%"
            lines.append(f"| {tier} | {stats['total']} | {stats['passed']} | {stats['failed']} | {stats['errors']} | {pr} |")
        lines.append("")

    # Patch statistics
    patch_stats = summary.get("patch_statistics", {})
    if patch_stats:
        ps = patch_stats.get("passing_fixes", {})
        fs = patch_stats.get("failing_attempts", {})
        if ps.get("count", 0) > 0 or fs.get("count", 0) > 0:
            lines.extend([
                "## Patch Size Analysis",
                "",
                "| Category | Count | Avg Files | Avg Lines Added | Avg Lines Removed |",
                "|----------|-------|-----------|-----------------|-------------------|",
            ])
            if ps.get("count", 0) > 0:
                lines.append(f"| Passing fixes | {ps['count']} | {ps['avg_files']} | {ps['avg_lines_added']} | {ps['avg_lines_removed']} |")
            if fs.get("count", 0) > 0:
                lines.append(f"| Failing attempts | {fs['count']} | {fs['avg_files']} | {fs['avg_lines_added']} | {fs['avg_lines_removed']} |")
            lines.append("")

    # Trajectory statistics
    traj_stats = summary.get("trajectory_statistics", {})
    if traj_stats:
        steps = traj_stats.get("steps", {})
        cost = traj_stats.get("cost", {})
        tokens = traj_stats.get("tokens", {})
        timing = traj_stats.get("timing", {})
        behavior = traj_stats.get("behavior", {})

        lines.extend([
            "## Agent Trajectory Statistics",
            "",
            "| Metric | Value |",
            "|--------|-------|",
            f"| Cases with trajectory | {traj_stats.get('cases_with_trajectory', 0)} |",
        ])
        if steps:
            lines.append(f"| Avg steps per case | {steps.get('avg')} |")
            lines.append(f"| Steps range | {steps.get('min')} - {steps.get('max')} |")
        if cost.get("total") is not None:
            lines.append(f"| Total cost | ${cost['total']:.4f} |")
            lines.append(f"| Avg cost per case | ${cost['avg']:.4f} |")
        if tokens.get("total") is not None:
            lines.append(f"| Total tokens | {tokens['total']:,} |")
            lines.append(f"| Avg input tokens | {tokens.get('avg_input', 'N/A'):,} |")
            lines.append(f"| Avg output tokens | {tokens.get('avg_output', 'N/A'):,} |")
        if timing.get("avg_inference_time_s") is not None:
            lines.append(f"| Avg inference time (s) | {timing['avg_inference_time_s']} |")
            lines.append(f"| Avg execution time (s) | {timing.get('avg_execution_time_s')} |")
        lines.append("")

        # Action distribution
        actions = behavior.get("action_distribution", {})
        if actions:
            lines.extend([
                "### Action Distribution",
                "",
                "| Action | Count |",
                "|--------|-------|",
            ])
            for action, count in actions.items():
                lines.append(f"| {action} | {count} |")
            lines.append(f"| **Build failures** | **{behavior.get('total_build_failures', 0)}** / {behavior.get('total_build_attempts', 0)} |")
            lines.append("")

    # Per-case results
    cases = summary.get("cases", [])
    if cases:
        lines.extend([
            "## Per-Case Results",
            "",
            "| Case | Result | Duration (s) | Steps | Cost | Tokens | Failure Reason |",
            "|------|--------|-------------|-------|------|--------|----------------|",
        ])
        for c in cases:
            reason = c.get("failure_reason", "")
            steps_used = c.get("steps_used") or ""
            cost_val = f"${c['cost']:.4f}" if c.get("cost") is not None else ""
            tokens_val = f"{c['tokens']:,}" if c.get("tokens") is not None else ""
            lines.append(f"| {c['case']} | {c['result']} | {c.get('duration_seconds', '')} | {steps_used} | {cost_val} | {tokens_val} | {reason} |")
        lines.append("")

    output_path = os.path.join(results_dir, "summary.md")
    with open(output_path, "w") as f:
        f.write("\n".join(lines))


DEFAULT_REGISTRY = Path(__file__).resolve().parent.parent / "registry" / "case_registry.json"


def aggregate(results_dir: str, registry_path: str | None = None) -> dict | None:
    """Write summary.json and summary.md for results_dir; return the summary."""
    results = load_results(results_dir)
    if not results:
        return None
    registry = load_registry(registry_path or str(DEFAULT_REGISTRY))
    summary = generate_summary_json(results, registry, results_dir)
    generate_summary_md(summary, results_dir)
    return summary


def main():
    if len(sys.argv) < 2:
        print("Usage: aggregate_results.py <results-dir> [registry-json]", file=sys.stderr)
        sys.exit(2)

    results_dir = sys.argv[1]
    registry_path = sys.argv[2] if len(sys.argv) > 2 else str(DEFAULT_REGISTRY)

    results = load_results(results_dir)
    if not results:
        print(f"No result.json files found in {results_dir}")
        sys.exit(0)

    registry = load_registry(registry_path)
    summary = generate_summary_json(results, registry, results_dir)
    generate_summary_md(summary, results_dir)

    overall = summary["overall"]
    print(f"Aggregated {overall['total']} results: {overall['passed']} passed, "
          f"{overall['failed']} failed, {overall['errors']} errors "
          f"({overall['pass_rate']*100:.1f}% pass rate over {overall['scored']} scored)")


if __name__ == "__main__":
    main()
