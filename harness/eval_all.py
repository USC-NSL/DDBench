#!/usr/bin/env python3
"""eval_all.py — backend of `bench.sh eval-all`: evaluate many patches in parallel.

Usage (normally through bench.sh):
    ./bench.sh eval-all --predictions preds.jsonl --out DIR [--jobs J] [--runs N]
                        [--timeout SECS] [--setup] [--no-reset]

Predictions: one JSON object per line.
    {"case": "<case-name>", "patch": "<unified diff text>"}
    {"case": "<case-name>", "patch_file": "<path to a .diff file>"}
Aliases: "instance_id" for "case", "model_patch" for "patch", "patch_path" for
"patch_file" (paths are relative to the predictions file). A "patch" value that
is not diff text but names an existing file is read as a patch file. An empty
patch evaluates the unmodified buggy worktree. Optional "model_name_or_path" is
recorded in the summary. Blank lines and lines starting with '#' are ignored.

Output:
    DIR/<case>/patch.diff     the patch that was evaluated
    DIR/<case>/result.json    `bench.sh eval --json` output (schema ddbench.eval/v1)
    DIR/<case>/eval.log       bench.sh eval console output
    DIR/<case>/logs/          per-run oracle logs
    DIR/summary.json, DIR/summary.md   aggregate (harness/aggregate_results.py)

Cases run in parallel (each case has its own Docker volumes and container);
each case appears at most once per predictions file.

Exit status: 0 = every case produced PASS or FAIL, 2 = at least one ERROR
(or a usage/input error).
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from pathlib import Path

HARNESS_DIR = Path(__file__).resolve().parent
CASES_ROOT = HARNESS_DIR.parent
sys.path.insert(0, str(HARNESS_DIR))
import aggregate_results  # noqa: E402

PRINT_LOCK = threading.Lock()


def log(msg: str) -> None:
    with PRINT_LOCK:
        print(msg, flush=True)


def now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def looks_like_diff(text: str) -> bool:
    return any(line.startswith(("diff --git ", "--- ", "+++ ", "@@ "))
               for line in text.splitlines()[:200])


def load_predictions(path: Path) -> list[dict]:
    preds, seen, errors = [], {}, []
    with open(path, encoding="utf-8") as f:
        for lineno, raw in enumerate(f, 1):
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            try:
                obj = json.loads(line)
            except ValueError as e:
                errors.append(f"line {lineno}: invalid JSON ({e})")
                continue
            if not isinstance(obj, dict):
                errors.append(f"line {lineno}: expected a JSON object")
                continue
            case = obj.get("case") or obj.get("instance_id")
            if not isinstance(case, str) or not case:
                errors.append(f"line {lineno}: missing \"case\"")
                continue
            if case in seen:
                errors.append(f"line {lineno}: duplicate case {case} (first on line {seen[case]})")
                continue
            seen[case] = lineno
            patch_text, patch_file = None, obj.get("patch_file") or obj.get("patch_path")
            patch = obj.get("patch", obj.get("model_patch"))
            if patch_file is None and isinstance(patch, str):
                candidate = (path.parent / patch).expanduser() if patch.strip() else None
                if (candidate is not None and "\n" not in patch.strip() and not looks_like_diff(patch)
                        and candidate.is_file()):
                    patch_file = str(candidate)
                else:
                    patch_text = patch
            if patch_file is not None:
                pf = Path(patch_file).expanduser()
                if not pf.is_absolute():
                    pf = path.parent / pf
                patch_file = str(pf)
            elif patch_text is None:
                errors.append(f"line {lineno}: {case}: need \"patch\" (diff text) or \"patch_file\"")
                continue
            preds.append({"line": lineno, "case": case, "patch_text": patch_text,
                          "patch_file": patch_file, "model": obj.get("model_name_or_path")})
    if errors:
        raise ValueError("\n".join(errors))
    return preds


def error_result(case: str, message: str, patch_file: str | None = None) -> dict:
    return {"schema": "ddbench.eval/v1", "case": case, "verdict": "ERROR", "exit_code": 2,
            "exit_codes": [], "n_runs": 0, "runs": [], "patch_applied": False,
            "patch_file": patch_file, "error": message, "duration_s": 0, "timestamp": now()}


def is_set_up(bench: str, case: str) -> bool:
    vol = subprocess.run(["bash", bench, "info", case, "volume"], capture_output=True, text=True)
    if vol.returncode != 0:
        return False
    return subprocess.run(["docker", "volume", "inspect", vol.stdout.strip()],
                          capture_output=True).returncode == 0


def evaluate(pred: dict, args, out_dir: Path) -> dict:
    case = pred["case"]
    case_out = out_dir / case
    case_out.mkdir(parents=True, exist_ok=True)
    patch_path = case_out / "patch.diff"
    result_path = case_out / "result.json"

    if not (CASES_ROOT / "cases" / case / "case.yaml").is_file():
        res = error_result(case, f"unknown case: {case}")
        result_path.write_text(json.dumps(res, indent=2) + "\n")
        return res
    try:
        if pred["patch_file"] is not None:
            data = Path(pred["patch_file"]).read_bytes()
        else:
            data = pred["patch_text"].encode("utf-8")
            if data and not data.endswith(b"\n"):
                data += b"\n"
        patch_path.write_bytes(data)
    except OSError as e:
        res = error_result(case, f"cannot read patch: {e}", pred["patch_file"])
        result_path.write_text(json.dumps(res, indent=2) + "\n")
        return res

    with open(case_out / "eval.log", "w") as console:
        if not is_set_up(args.bench, case):
            if not args.setup:
                res = error_result(case, f"{case} is not set up (run ./bench.sh setup {case}, "
                                         "or pass --setup)", str(patch_path))
                result_path.write_text(json.dumps(res, indent=2) + "\n")
                return res
            log(f"[setup] {case}")
            rc = subprocess.run(["bash", args.bench, "setup", case], stdout=console,
                                stderr=subprocess.STDOUT).returncode
            if rc != 0:
                res = error_result(case, f"bench.sh setup failed (exit {rc}); see eval.log",
                                   str(patch_path))
                result_path.write_text(json.dumps(res, indent=2) + "\n")
                return res

        cmd = ["bash", args.bench, "eval", case, "--patch", str(patch_path),
               "--runs", str(args.runs), "--json", str(result_path),
               "--log-dir", str(case_out / "logs"), "--timeout", str(args.timeout)]
        if args.no_reset:
            cmd.append("--no-reset")
        log(f"[start] {case}")
        t0 = time.time()
        rc = subprocess.run(cmd, stdout=console, stderr=subprocess.STDOUT).returncode

    try:
        res = json.loads(result_path.read_text())
    except (OSError, ValueError):
        res = error_result(case, f"bench.sh eval exited {rc} without a result; see eval.log",
                           str(patch_path))
        res["duration_s"] = int(time.time() - t0)
        result_path.write_text(json.dumps(res, indent=2) + "\n")
    if pred.get("model"):
        res["model_name_or_path"] = pred["model"]
        result_path.write_text(json.dumps(res, indent=2) + "\n")
    return res


def main() -> int:
    ap = argparse.ArgumentParser(prog="bench.sh eval-all",
                                 description="Evaluate a JSONL file of patches against DDBench cases.")
    ap.add_argument("--bench", default=str(CASES_ROOT / "bench.sh"), help=argparse.SUPPRESS)
    ap.add_argument("--predictions", required=True, type=Path, help="JSONL predictions file")
    ap.add_argument("--out", required=True, type=Path, help="output directory")
    default_jobs = max(1, (os.cpu_count() or 10) // 10)
    ap.add_argument("--jobs", type=int, default=default_jobs,
                    help=f"cases evaluated in parallel (default: {default_jobs}; each case uses up to 10 CPUs)")
    ap.add_argument("--runs", type=int, default=1, help="oracle runs per case (default: 1)")
    ap.add_argument("--timeout", type=int, default=int(os.environ.get("BENCH_RUN_TIMEOUT", 3600)),
                    help="timeout per oracle run in seconds (default: 3600)")
    ap.add_argument("--setup", action="store_true", help="run bench.sh setup for cases that are not set up")
    ap.add_argument("--no-reset", action="store_true", help="leave each worktree patched afterwards")
    args = ap.parse_args()

    if args.jobs < 1 or args.runs < 1 or args.timeout < 0:
        ap.error("--jobs and --runs must be >= 1, --timeout >= 0")
    try:
        preds = load_predictions(args.predictions)
    except (OSError, ValueError) as e:
        print(f"ERROR: cannot use {args.predictions}:\n{e}", file=sys.stderr)
        return 2
    if not preds:
        print(f"ERROR: no predictions in {args.predictions}", file=sys.stderr)
        return 2

    out_dir = args.out.resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    started = now()
    log(f"=== eval-all: {len(preds)} case(s), {args.jobs} job(s), {args.runs} run(s) each -> {out_dir}")

    results = {}
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        futures = {pool.submit(evaluate, p, args, out_dir): p["case"] for p in preds}
        for fut in as_completed(futures):
            case = futures[fut]
            try:
                res = fut.result()
            except Exception as e:  # keep going: one broken case must not stop the batch
                res = error_result(case, f"internal error: {e}")
                (out_dir / case).mkdir(parents=True, exist_ok=True)
                (out_dir / case / "result.json").write_text(json.dumps(res, indent=2) + "\n")
            results[case] = res
            log(f"[done]  {case}: {res.get('verdict')}"
                + (f" ({res['error']})" if res.get("error") else ""))

    summary = aggregate_results.aggregate(str(out_dir))
    if summary is not None:
        summary["eval_all"] = {
            "predictions": str(args.predictions.resolve()),
            "runs_per_case": args.runs, "jobs": args.jobs, "timeout_s": args.timeout,
            "started_at": started, "finished_at": now(),
        }
        with open(out_dir / "summary.json", "w") as f:
            json.dump(summary, f, indent=2)
        o = summary["overall"]
        log(f"=== eval-all done: {o['passed']} PASS, {o['failed']} FAIL, {o['errors']} ERROR "
            f"(pass rate {o['pass_rate'] * 100:.1f}% of {o['scored']} scored)")
        log(f"    {out_dir / 'summary.md'}")
    return 2 if any(r.get("verdict") == "ERROR" for r in results.values()) else 0


if __name__ == "__main__":
    sys.exit(main())
