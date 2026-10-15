#!/usr/bin/env python3
"""oracle_validation_report.py — build registry/oracle_validation.json and
docs/oracle-validation.md from `bench.sh validate-oracle --json` outputs.

Usage:
    for c in $(ls cases); do
        ./bench.sh validate-oracle "$c" --runs 3 --json "out/$c.json"
    done
    python3 scripts/oracle_validation_report.py out/ \
        [--note CASE=TEXT ...] [--environment TEXT]

Cases without a JSON file are listed as NOT-RUN (with their --note, if any).
Standard library only.
"""

from __future__ import annotations

import argparse
import json
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
JSON_OUT = ROOT / "registry" / "oracle_validation.json"
MD_OUT = ROOT / "docs" / "oracle-validation.md"
ORDER = ["SOUND", "FLAKY", "UNSOUND", "ERROR", "NO-GOLD", "NOT-RUN"]


def side(d: dict | None) -> dict | None:
    if not d:
        return None
    runs = d.get("runs") or []
    return {
        "expected": d.get("expected"),
        "matched": d.get("matched", 0),
        "runs": len(runs),
        "errors": d.get("errors", 0),
        "exit_codes": d.get("exit_codes", []),
        "durations_s": [r.get("duration_s") for r in runs],
        **({"patch_applied": d["patch_applied"]} if "patch_applied" in d else {}),
    }


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("results_dir", type=Path)
    ap.add_argument("--note", action="append", default=[], metavar="CASE=TEXT")
    ap.add_argument("--environment", default="")
    ap.add_argument("--footer", default="", help="Markdown appended under a 'Notes' heading")
    args = ap.parse_args()
    notes = dict(n.split("=", 1) for n in args.note)

    cases = sorted(d.name for d in (ROOT / "cases").iterdir() if (d / "case.yaml").is_file())
    entries = []
    for case in cases:
        f = args.results_dir / f"{case}.json"
        if not f.exists():
            entries.append({"case": case, "status": "NOT-RUN", "buggy": None, "gold": None,
                            "date": None, "note": notes.get(case, "")})
            continue
        r = json.loads(f.read_text())
        entries.append({
            "case": case,
            "status": r["status"],
            "runs_per_side": r.get("runs_per_side"),
            "buggy": side(r.get("buggy")),
            "gold": side(r.get("gold")),
            "detail": r.get("detail"),
            "duration_s": r.get("duration_s"),
            "date": (r.get("timestamp") or "")[:10] or None,
            "note": notes.get(case, ""),
        })

    counts = Counter(e["status"] for e in entries)
    data = {
        "schema": "ddbench.oracle-validation/v1",
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "generator": "scripts/oracle_validation_report.py",
        "method": "bench.sh validate-oracle: the buggy worktree must FAIL in every run and "
                  "cases-solution/<case>/gold.patch must PASS in every run (offline scoring).",
        "environment": args.environment,
        "counts": {s: counts.get(s, 0) for s in ORDER if counts.get(s)},
        "cases": entries,
    }
    JSON_OUT.write_text(json.dumps(data, indent=2) + "\n")

    def frac(s):
        return f"{s['matched']}/{s['runs']}" if s else "—"

    lines = [
        "# Oracle validation",
        "",
        "Every case's oracle was checked with `./bench.sh validate-oracle <case> --runs N`:",
        "the pristine buggy worktree must FAIL in all N runs, and the worktree with",
        "`cases-solution/<case>/gold.patch` applied must PASS in all N runs. Runs use the",
        "normal scoring path (`bench.sh reproduce`: incremental rebuild, then the oracle,",
        "offline with the case's dependency cache).",
        "",
        "| Status | Meaning |",
        "|--------|---------|",
        "| SOUND | buggy FAIL N/N and gold PASS N/N |",
        "| FLAKY | mixed results on at least one side |",
        "| UNSOUND | buggy never FAILs or gold never PASSes |",
        "| ERROR | a run returned ERROR, or gold.patch does not apply |",
        "| NO-GOLD | no gold.patch (buggy side only) |",
        "| NOT-RUN | not validated in this run (see note) |",
        "",
        f"Machine-readable results: [`registry/oracle_validation.json`](../registry/oracle_validation.json).",
        "",
    ]
    if args.environment:
        lines += [f"Environment: {args.environment}", ""]
    lines += ["## Summary", "", "| Status | Cases |", "|--------|------:|"]
    for s in ORDER:
        if counts.get(s):
            lines.append(f"| {s} | {counts[s]} |")
    lines += [f"| **Total** | **{len(entries)}** |", "", "## Per case", "",
              "| Case | Status | Buggy FAIL | Gold PASS | Duration (s) | Date | Note |",
              "|------|--------|-----------:|----------:|-------------:|------|------|"]
    for e in entries:
        lines.append(f"| `{e['case']}` | {e['status']} | {frac(e['buggy'])} | {frac(e['gold'])} | "
                     f"{e.get('duration_s') or '—'} | {e['date'] or '—'} | {e['note']} |")
    lines.append("")
    if args.footer:
        lines += ["## Notes", "", args.footer.strip(), ""]
    MD_OUT.parent.mkdir(parents=True, exist_ok=True)
    MD_OUT.write_text("\n".join(lines))
    print(f"wrote {JSON_OUT.relative_to(ROOT)} and {MD_OUT.relative_to(ROOT)}: "
          + ", ".join(f"{s} {counts[s]}" for s in ORDER if counts.get(s)))


if __name__ == "__main__":
    main()
