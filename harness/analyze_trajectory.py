#!/usr/bin/env python3
"""analyze_trajectory.py — Extract timing, cost, and behavioral metrics from a trajectory.

Usage:
    python3 scripts/analyze_trajectory.py <trajectory.traj.json> <output-dir>

Reads:
    trajectory.traj.json — mini-swe-agent trajectory file

Outputs:
    <output-dir>/trajectory_analysis.json — per-step and aggregate metrics

Robust: outputs whatever it can parse even if the trajectory is partial or malformed.
"""

import json
import re
import sys
import traceback
from pathlib import Path


# ── Command classification ──────────────────────────────────────────────────

def _command_writes_files(cmd: str) -> bool:
    """Detect inline scripts that write to source files (Python, Perl, Ruby).

    Pattern-based matching misses these because the write call is buried
    inside an interpreter heredoc or -c flag.
    """
    if re.search(r"\bpython[23]?\b", cmd):
        if re.search(r"write_text|\.write\s*\(|open\s*\(", cmd, re.DOTALL):
            return True
    if re.search(r"\bruby\b", cmd):
        if re.search(r"File\.write|File\.open.*['\"][wxa]", cmd, re.DOTALL):
            return True
    return False


# Patterns ordered by specificity; first match wins.
# "edit" MUST precede "build" so that compound commands like
#   `sed -i ... && ./REBUILD.sh`  or  `cat <<EOF > file && make`
# are classified as edits (the file mutation is the primary action).
COMMAND_PATTERNS = [
    ("submit",  [r"COMPLETE_TASK_AND_SUBMIT"]),
    ("edit",    [r"\bsed\s+-i\b",
                 r"\bpatch\b",
                 r"\bperl\b.*\s-[a-z0-9]*i",   # perl -pi, -0pi, -i, etc.
                 r"\bcat\s*<<",                 # heredoc (file creation)
                 r"\btee\b",
                 r">\s*\S+\.\w+"]),             # redirect to file with extension
    ("build",   [r"\./REBUILD\.sh", r"\bmake\b", r"\bgo\s+build\b", r"\bcargo\s+build\b",
                 r"\bmvn\b", r"\bgradle\b", r"\bcmake\b"]),
    ("test",    [r"\bgo\s+test\b", r"\bpytest\b", r"\bcargo\s+test\b", r"\bnpm\s+test\b",
                 r"\bmake\s+test\b"]),
    ("read",    [r"\bcat\s", r"\bhead\b", r"\btail\b", r"\bnl\s", r"\bless\b",
                 r"\bbatcat\b", r"\bmore\b"]),
    ("explore", [r"\bgrep\b", r"\brg\b", r"\bfind\s", r"\bls\b", r"\btree\b",
                 r"\bfd\b", r"\bwc\b", r"\bdu\b", r"\bfile\b"]),
]


def classify_command(cmd: str) -> str:
    """Classify a bash command into a category."""
    for category, patterns in COMMAND_PATTERNS:
        for pat in patterns:
            if re.search(pat, cmd):
                return category
    if _command_writes_files(cmd):
        return "edit"
    return "other"


# ── Safe accessors ──────────────────────────────────────────────────────────

def safe_int(val, default=0):
    """Safely convert to int."""
    if val is None:
        return default
    try:
        return int(val)
    except (ValueError, TypeError):
        return default


def safe_float(val, default=0.0):
    """Safely convert to float."""
    if val is None:
        return default
    try:
        return float(val)
    except (ValueError, TypeError):
        return default


# ── Trajectory parsing ──────────────────────────────────────────────────────

def parse_trajectory(traj: dict) -> dict:
    """Extract per-step and aggregate metrics from a trajectory.

    Designed to be resilient: parses whatever is available and skips
    malformed steps rather than aborting entirely.
    """
    messages = traj.get("messages") or []
    info = traj.get("info") or {}

    steps = []
    total_input_tokens = 0
    total_output_tokens = 0
    total_cost = 0.0
    parse_warnings = []

    # Walk assistant/user pairs
    prev_observation_ts = None
    for i, msg in enumerate(messages):
        role = msg.get("role", "")

        if role == "assistant":
            try:
                extra = msg.get("extra") or {}
                ts = extra.get("timestamp")
                actions = extra.get("actions") or []
                response = extra.get("response") or {}
                usage = response.get("usage") or {}

                # Tokens and cost — tolerate missing or non-numeric values
                prompt_tokens = safe_int(usage.get("prompt_tokens"))
                completion_tokens = safe_int(usage.get("completion_tokens"))
                # Cost lives at extra.cost (LiteLLM-computed), NOT usage.cost
                step_cost = safe_float(extra.get("cost"))
                prompt_details = usage.get("prompt_tokens_details") or {}
                cached_tokens = safe_int(prompt_details.get("cached_tokens"))

                total_input_tokens += prompt_tokens
                total_output_tokens += completion_tokens
                total_cost += step_cost

                # Command — guard against malformed actions
                command = ""
                if actions and isinstance(actions, list) and len(actions) > 0:
                    action = actions[0]
                    if isinstance(action, dict):
                        command = action.get("command", "")
                category = classify_command(command) if command else "empty"

                # LLM inference latency
                inference_time = None
                if prev_observation_ts is not None and ts is not None:
                    try:
                        inference_time = round(float(ts) - float(prev_observation_ts), 3)
                        if inference_time < 0:
                            parse_warnings.append(f"Step {len(steps)+1}: negative inference time ({inference_time}s)")
                            inference_time = None
                    except (ValueError, TypeError):
                        pass

                # Look ahead for the next user message to get execution time
                exec_time = None
                exec_returncode = None
                next_user_ts = None
                if i + 1 < len(messages) and messages[i + 1].get("role") == "user":
                    next_extra = messages[i + 1].get("extra") or {}
                    next_user_ts = next_extra.get("timestamp")
                    exec_returncode = next_extra.get("returncode")
                    if ts is not None and next_user_ts is not None:
                        try:
                            exec_time = round(float(next_user_ts) - float(ts), 3)
                            if exec_time < 0:
                                parse_warnings.append(f"Step {len(steps)+1}: negative execution time ({exec_time}s)")
                                exec_time = None
                        except (ValueError, TypeError):
                            pass

                step = {
                    "step": len(steps) + 1,
                    "command": command,
                    "category": category,
                    "inference_time_s": inference_time,
                    "execution_time_s": exec_time,
                    "returncode": exec_returncode,
                    "prompt_tokens": prompt_tokens,
                    "completion_tokens": completion_tokens,
                    "cached_tokens": cached_tokens,
                    "cost": step_cost,
                }
                steps.append(step)

                # Update prev_observation_ts from the paired user message
                if next_user_ts is not None:
                    prev_observation_ts = next_user_ts

            except Exception as e:
                parse_warnings.append(f"Step at message {i}: parse error: {e}")
                continue

        elif role == "user" and prev_observation_ts is None:
            # First user message (the initial prompt) — seed the timestamp
            extra = msg.get("extra") or {}
            prev_observation_ts = extra.get("timestamp")

    # ── Aggregate metrics ───────────────────────────────────────────────────

    # Action distribution
    action_counts: dict[str, int] = {}
    for s in steps:
        cat = s["category"]
        action_counts[cat] = action_counts.get(cat, 0) + 1

    # Build attempts and failures
    build_steps = [s for s in steps if s["category"] == "build"]
    build_attempts = len(build_steps)
    build_failures = sum(1 for s in build_steps if s["returncode"] not in (None, 0))

    # Edit count
    edit_count = action_counts.get("edit", 0)

    # Total timing
    inference_times = [s["inference_time_s"] for s in steps if s["inference_time_s"] is not None]
    execution_times = [s["execution_time_s"] for s in steps if s["execution_time_s"] is not None]
    total_inference_time = round(sum(inference_times), 3) if inference_times else None
    total_execution_time = round(sum(execution_times), 3) if execution_times else None

    # Cache hit rate
    total_cached = sum(s["cached_tokens"] for s in steps)
    cache_hit_rate = round(total_cached / total_input_tokens, 4) if total_input_tokens > 0 else 0.0

    # Exit status
    exit_status = info.get("exit_status", "unknown")
    model_stats = info.get("model_stats") or {}

    analysis = {
        "steps_used": len(steps),
        "step_limit": (info.get("config") or {}).get("agent", {}).get("step_limit"),
        "exit_status": exit_status,
        "api_calls": model_stats.get("api_calls", len(steps)),
        "timing": {
            "total_inference_time_s": total_inference_time,
            "total_execution_time_s": total_execution_time,
            "avg_inference_time_s": round(sum(inference_times) / len(inference_times), 3) if inference_times else None,
            "avg_execution_time_s": round(sum(execution_times) / len(execution_times), 3) if execution_times else None,
        },
        "tokens": {
            "total_input_tokens": total_input_tokens,
            "total_output_tokens": total_output_tokens,
            "total_tokens": total_input_tokens + total_output_tokens,
            "cached_tokens": total_cached,
            "cache_hit_rate": cache_hit_rate,
        },
        "cost": {
            "total_cost": round(total_cost, 6),
        },
        "behavior": {
            "action_distribution": dict(sorted(action_counts.items(), key=lambda x: -x[1])),
            "build_attempts": build_attempts,
            "build_failures": build_failures,
            "edit_count": edit_count,
        },
        "per_step": steps,
    }

    if parse_warnings:
        analysis["warnings"] = parse_warnings

    return analysis


# ── Main ────────────────────────────────────────────────────────────────────

def main():
    if len(sys.argv) < 3:
        print("Usage: analyze_trajectory.py <trajectory.traj.json> <output-dir>", file=sys.stderr)
        sys.exit(1)

    traj_path = sys.argv[1]
    output_dir = sys.argv[2]

    if not Path(traj_path).exists():
        print(f"Trajectory not found: {traj_path}", file=sys.stderr)
        sys.exit(1)

    Path(output_dir).mkdir(parents=True, exist_ok=True)
    output_path = Path(output_dir) / "trajectory_analysis.json"

    # Try to parse; on any top-level error, write a minimal output with the error
    try:
        with open(traj_path) as f:
            traj = json.load(f)
    except (json.JSONDecodeError, OSError) as e:
        print(f"  WARNING: Cannot read trajectory: {e}", file=sys.stderr)
        error_analysis = {
            "steps_used": 0,
            "error": f"Failed to read trajectory: {e}",
        }
        with open(output_path, "w") as f:
            json.dump(error_analysis, f, indent=2)
        sys.exit(0)  # Non-fatal — we wrote what we could

    try:
        analysis = parse_trajectory(traj)
    except Exception as e:
        print(f"  WARNING: Trajectory parse error: {e}", file=sys.stderr)
        traceback.print_exc(file=sys.stderr)
        error_analysis = {
            "steps_used": 0,
            "error": f"Parse error: {e}",
        }
        with open(output_path, "w") as f:
            json.dump(error_analysis, f, indent=2)
        sys.exit(0)  # Non-fatal

    with open(output_path, "w") as f:
        json.dump(analysis, f, indent=2)

    # Print summary
    t = analysis["timing"]
    b = analysis["behavior"]
    c = analysis["cost"]
    tok = analysis["tokens"]
    warnings = analysis.get("warnings", [])
    print(f"  Trajectory: {analysis['steps_used']} steps, "
          f"inference={t['total_inference_time_s']}s, "
          f"exec={t['total_execution_time_s']}s, "
          f"cost=${c['total_cost']:.4f}, "
          f"tokens={tok['total_tokens']}, "
          f"builds={b['build_attempts']}({b['build_failures']} failed), "
          f"edits={b['edit_count']}")
    if warnings:
        print(f"  Warnings: {len(warnings)}")
        for w in warnings:
            print(f"    - {w}")


if __name__ == "__main__":
    main()
