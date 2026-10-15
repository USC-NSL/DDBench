#!/usr/bin/env bash
# score_case.sh -- Score one case after an agent has modified its worktree.
#
# Usage: harness/score_case.sh <case-name> <results-dir> [options]
#
# Assumes `bench.sh setup <case>` has run and an agent has edited the worktree
# (bench.sh agent). Steps:
#   1. extract_patch.sh  -> <results-dir>/<case>/patch.diff + patch_metadata.json
#   2. analyze_trajectory.py, if <results-dir>/<case>/trajectory.traj.json exists
#   3. bench.sh reproduce <case> (with a timeout) -> verdict
#   4. write <results-dir>/<case>/result.json
#   5. bench.sh reset <case> (unless --no-reset)
#
# Verdicts (from the bench.sh reproduce exit code):
#   0 -> PASS, 1 -> FAIL, 2 -> ERROR (infrastructure / inconclusive; not a model
#   failure), timeout -> FAIL (failure_reason "timeout").
# With --agent-timeout the agent was killed by the runner's timeout; the case is
# recorded as FAIL (failure_reason "agent_timeout") without running the oracle.
#
# Exit code: 0 when a result.json was written (the verdict is in the JSON),
# 2 on usage errors.
set -euo pipefail

HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CASES_ROOT="${DDBENCH_ROOT:-$(cd "$HARNESS_DIR/.." && pwd)}"
BENCH="$CASES_ROOT/bench.sh"

usage() {
    cat <<EOF
Usage: $0 <case-name> <results-dir> [options]

Options:
  --no-reset        Don't reset the worktree after scoring
  --no-extract      Don't extract the patch (faster)
  --timeout N       Timeout for bench.sh reproduce in seconds (default: 3600)
  --agent-timeout   The agent was killed by timeout: record FAIL without scoring
  -h, --help        Show this help message
EOF
    exit 2
}

[ $# -ge 2 ] || usage
CASE_NAME="$1"
RESULTS_DIR="$2"
shift 2

DO_RESET=true
DO_EXTRACT=true
TIMEOUT=3600
AGENT_TIMEOUT=false

while [ $# -gt 0 ]; do
    case "$1" in
        --no-reset)      DO_RESET=false; shift ;;
        --no-extract)    DO_EXTRACT=false; shift ;;
        --timeout)       TIMEOUT="$2"; shift 2 ;;
        --agent-timeout) AGENT_TIMEOUT=true; shift ;;
        -h|--help)       usage ;;
        *)               echo "Unknown option: $1" >&2; usage ;;
    esac
done

CASE_DIR="$RESULTS_DIR/$CASE_NAME"
mkdir -p "$CASE_DIR"

echo "=== Scoring: $CASE_NAME ==="

# ── Step 1: Extract the patch ───────────────────────────────────────────────
if [ "$DO_EXTRACT" = true ]; then
    echo "  Extracting patch ..."
    if bash "$HARNESS_DIR/extract_patch.sh" "$CASE_NAME" "$CASE_DIR" >"$CASE_DIR/extract.log" 2>&1; then
        echo "  $(tail -n 1 "$CASE_DIR/extract.log")"
    else
        echo "  WARNING: patch extraction failed (non-fatal, see extract.log)."
    fi
fi

# ── Step 2: Analyze the trajectory ──────────────────────────────────────────
TRAJ_FILE="$CASE_DIR/trajectory.traj.json"
if [ -f "$TRAJ_FILE" ]; then
    echo "  Analyzing trajectory ..."
    python3 "$HARNESS_DIR/analyze_trajectory.py" "$TRAJ_FILE" "$CASE_DIR" 2>"$CASE_DIR/analyze_stderr.log" \
        || echo "  WARNING: trajectory analysis failed (non-fatal)."
fi

# ── Step 3: Run the oracle ──────────────────────────────────────────────────
RESULT="FAIL"
REPRODUCE_EXIT=1
REPRODUCE_DURATION=0
FAILURE_REASON=""

if [ "$AGENT_TIMEOUT" = true ]; then
    echo "  Agent timed out: skipping the oracle, recording FAIL."
    FAILURE_REASON="agent_timeout"
else
    echo "  Running bench.sh reproduce (timeout ${TIMEOUT}s) ..."
    START=$(date +%s)
    REPRODUCE_EXIT=0
    timeout --kill-after=30 "$TIMEOUT" bash "$BENCH" reproduce "$CASE_NAME" \
        >"$CASE_DIR/reproduce_stdout.log" 2>"$CASE_DIR/reproduce_stderr.log" || REPRODUCE_EXIT=$?
    REPRODUCE_DURATION=$(( $(date +%s) - START ))
    case "$REPRODUCE_EXIT" in
        0) RESULT="PASS" ;;
        1) RESULT="FAIL" ;;
        124|137)
            RESULT="FAIL"; FAILURE_REASON="timeout"
            # The oracle container outlives a killed docker client: remove it.
            CNAME=$(bash "$BENCH" info "$CASE_NAME" container)
            docker rm -f "$CNAME" "$CNAME-build" >/dev/null 2>&1 || true
            echo "  reproduce timed out after ${TIMEOUT}s" ;;
        *) RESULT="ERROR"; FAILURE_REASON="oracle_error" ;;
    esac
fi

if [ -z "$FAILURE_REASON" ] && [ "$RESULT" = "FAIL" ]; then
    if grep -qiE "does not build|does not compile|build failed|compilation (error|failure)|cannot find symbol" \
            "$CASE_DIR/reproduce_stdout.log" 2>/dev/null; then
        FAILURE_REASON="build_failure"
    else
        FAILURE_REASON="test_failure"
    fi
fi

echo "  Result: $RESULT (exit=$REPRODUCE_EXIT, ${REPRODUCE_DURATION}s)"

# ── Step 4: result.json ─────────────────────────────────────────────────────
python3 - "$CASE_NAME" "$RESULT" "$REPRODUCE_EXIT" "$REPRODUCE_DURATION" \
         "$FAILURE_REASON" "$CASE_DIR" "$AGENT_TIMEOUT" <<'PYTHON'
import json, os, sys
from datetime import datetime, timezone

case_name, result, exit_code, duration, failure_reason, case_dir, agent_timeout = sys.argv[1:8]

def load(name):
    path = os.path.join(case_dir, name)
    if not os.path.exists(path):
        return {}
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError) as e:
        print(f"  WARNING: could not read {name}: {e}", file=sys.stderr)
        return {}

summary = ""
try:
    with open(os.path.join(case_dir, "reproduce_stdout.log"), errors="replace") as f:
        lines = [l.strip() for l in f if l.strip()]
    marked = [l for l in lines if l.split(":", 1)[0] in ("PASS", "FAIL", "ERROR")]
    summary = (marked or lines or [""])[-1][:300]
except OSError:
    pass

data = {
    "case": case_name,
    "result": result,            # PASS | FAIL | ERROR
    "verdict": result,           # same value; the key used by bench.sh eval
    "exit_code": int(exit_code),
    "duration_seconds": int(duration),
    "summary": summary,
    "scored_at": datetime.now(timezone.utc).isoformat(),
}
if agent_timeout == "true":
    data["agent_timeout"] = True
if failure_reason:
    data["failure_reason"] = failure_reason

patch_meta = load("patch_metadata.json")
if patch_meta:
    data["patch_metadata"] = patch_meta

traj = load("trajectory_analysis.json")
if traj and not traj.get("error"):
    data["steps_used"] = traj.get("steps_used")
    data["exit_status"] = traj.get("exit_status")
    data["cost"] = (traj.get("cost") or {}).get("total_cost")
    data["tokens"] = traj.get("tokens") or {}
    data["timing"] = traj.get("timing") or {}
    data["behavior"] = traj.get("behavior") or {}

out = os.path.join(case_dir, "result.json")
with open(out, "w") as f:
    json.dump(data, f, indent=2)
print(f"  Result written to {out}")
PYTHON

# ── Step 5: Reset ───────────────────────────────────────────────────────────
if [ "$DO_RESET" = true ]; then
    echo "  Resetting worktree ..."
    bash "$BENCH" reset "$CASE_NAME" >"$CASE_DIR/reset_stdout.log" 2>&1 || \
        echo "  WARNING: reset failed (check $CASE_DIR/reset_stdout.log)"
fi

echo "=== Done: $CASE_NAME -> $RESULT ==="
