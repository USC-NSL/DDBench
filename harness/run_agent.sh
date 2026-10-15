#!/usr/bin/env bash
# run_agent.sh -- Batch runner for mini-swe-agent on DDBench cases.
#
# Per case: setup -> reset -> agent (with timeout) -> score -> reset.
#
# Usage:
#   harness/run_agent.sh <case-name> [options]           Run on a single case
#   harness/run_agent.sh --surface <tier> [options]      Run on all cases of a tier
#
# Run `harness/run_agent.sh --help` for the options.
set -euo pipefail

HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CASES_ROOT="${DDBENCH_ROOT:-$(cd "$HARNESS_DIR/.." && pwd)}"
BENCH="$CASES_ROOT/bench.sh"
REGISTRY="$CASES_ROOT/registry/case_registry.json"
CONFIG_DIR="${DDBENCH_CONFIG_DIR:-$HARNESS_DIR/configs}"
DEFAULT_CONFIG="$CONFIG_DIR/ddbench_prompt.yaml"
CONTEXT_CONFIG="$CONFIG_DIR/ddbench_prompt_context.yaml"
RESULTS_ROOT="${DDBENCH_RESULTS_DIR:-$CASES_ROOT/results}"

# ── Signal handling ────────────────────────────────────────────────────────
CURRENT_CASE=""        # Track which case is active for cleanup
INTERRUPTED=false      # Flag to break the run loop
AGENT_PID=""           # PID of the setsid+timeout process group leader
NO_RESET=false

cleanup_on_interrupt() {
    if [ "$INTERRUPTED" = true ]; then
        # Second Ctrl+C: force exit immediately
        echo ""
        echo "Force exit."
        exit 130
    fi
    INTERRUPTED=true
    echo ""
    echo ">>> Interrupted! Cleaning up ..."

    # 1. Kill the agent process group if running
    if [ -n "$AGENT_PID" ] && kill -0 "$AGENT_PID" 2>/dev/null; then
        echo "  Killing agent process (PID $AGENT_PID) ..."
        kill -TERM -- -"$AGENT_PID" 2>/dev/null || true
        wait "$AGENT_PID" 2>/dev/null || true
    fi

    # 2. Stop the Docker container
    if [ -n "$CURRENT_CASE" ]; then
        echo "  Stopping container for $CURRENT_CASE ..."
        bash "$BENCH" stop "$CURRENT_CASE" >/dev/null 2>&1 || true

        # 3. Reset worktree to vanilla buggy state
        if [ "$NO_RESET" = false ]; then
            echo "  Resetting $CURRENT_CASE to buggy state ..."
            timeout 120 bash "$BENCH" reset "$CURRENT_CASE" >/dev/null 2>&1 || true
        fi
    fi

    echo "  Cleanup complete."
}

trap cleanup_on_interrupt INT TERM

# ── Argument parsing ────────────────────────────────────────────────────────

usage() {
    cat <<EOF
Usage: $0 <case-name> [options]
       $0 --surface <tier1|tier2|tier3|tier1,tier2|all> [options]

Run mini-swe-agent on DDBench cases with full orchestration:
  setup -> reset -> agent -> score -> reset (per case)

Options:
  --model <name>         Set/override MSWEA_MODEL_NAME (litellm model name)
  --config <path>        Agent config (default: $DEFAULT_CONFIG;
                         with --context: $CONTEXT_CONFIG)
  --timeout <seconds>    Agent timeout per case (default: 1800)
  --score-timeout <s>    Oracle timeout per case when scoring (default: 3600)
  --results-dir <dir>    Results directory
                         (default: \$DDBENCH_RESULTS_DIR/mini-swe-agent/<model>/<date>,
                          DDBENCH_RESULTS_DIR defaults to $RESULTS_ROOT)
  --skip-setup           Skip bench.sh setup (assume already done)
  --no-reset             Don't reset the worktree after scoring
  --host-network         Use host network for the agent container (reach host localhost)
  --context              Mount context/ and use the context-aware prompt and config
  --dry-run              Print the steps without executing them
  -h, --help             Show this help

Environment:
  MSWEA_MODEL_NAME       Required (except for --dry-run). Example:
                         anthropic/claude-sonnet-4-20250514
  DDBENCH_RESULTS_DIR    Root for default results directories
  DDBENCH_CONFIG_DIR     Directory holding the agent configs (default: harness/configs)
  Provider API keys      ANTHROPIC_API_KEY, OPENAI_API_KEY, ... (see bench.sh help)

Examples:
  MSWEA_MODEL_NAME=anthropic/claude-sonnet-4-20250514 $0 --surface tier1
  $0 raft-358-negative-log-range --model openai/gpt-4o --context
  $0 --surface tier1 --dry-run
EOF
    exit "${1:-2}"
}

CASE_NAME=""
SURFACE=""
MODEL_OVERRIDE=""
CONFIG=""
AGENT_TIMEOUT=1800
SCORE_TIMEOUT=3600
RESULTS_DIR=""
SKIP_SETUP=false
HOST_NETWORK=false
DEBUG_CONTEXT=false
DRY_RUN=false

while [ $# -gt 0 ]; do
    case "$1" in
        --surface)       SURFACE="$2"; shift 2 ;;
        --model)         MODEL_OVERRIDE="$2"; shift 2 ;;
        --config)        CONFIG="$2"; shift 2 ;;
        --timeout)       AGENT_TIMEOUT="$2"; shift 2 ;;
        --score-timeout) SCORE_TIMEOUT="$2"; shift 2 ;;
        --results-dir)   RESULTS_DIR="$2"; shift 2 ;;
        --skip-setup)    SKIP_SETUP=true; shift ;;
        --no-reset)      NO_RESET=true; shift ;;
        --host-network)  HOST_NETWORK=true; shift ;;
        --context)       DEBUG_CONTEXT=true; shift ;;
        --dry-run)       DRY_RUN=true; shift ;;
        -h|--help)       usage 0 ;;
        -*)              echo "Unknown option: $1" >&2; usage ;;
        *)
            [ -z "$CASE_NAME" ] || { echo "ERROR: Multiple case names given" >&2; usage; }
            CASE_NAME="$1"
            shift
            ;;
    esac
done

# Must specify either a case or a surface
[ -n "$CASE_NAME" ] || [ -n "$SURFACE" ] || { echo "ERROR: Specify a case name or --surface" >&2; usage; }
if [ -n "$CASE_NAME" ] && [ -n "$SURFACE" ]; then
    echo "ERROR: Specify either a case or --surface, not both" >&2; usage
fi

# ── Model ───────────────────────────────────────────────────────────────────

if [ -n "$MODEL_OVERRIDE" ]; then
    export MSWEA_MODEL_NAME="$MODEL_OVERRIDE"
fi

if [ -z "${MSWEA_MODEL_NAME:-}" ]; then
    if [ "$DRY_RUN" = true ]; then
        MSWEA_MODEL_NAME="<unset>"
    else
        echo "ERROR: MSWEA_MODEL_NAME is required but not set." >&2
        echo "" >&2
        echo "Set it via environment variable or --model flag:" >&2
        echo "  export MSWEA_MODEL_NAME=anthropic/claude-sonnet-4-20250514" >&2
        echo "  $0 --surface tier1 --model openai/gpt-4o" >&2
        exit 2
    fi
fi

# ── Config ──────────────────────────────────────────────────────────────────

if [ -z "$CONFIG" ]; then
    if [ "$DEBUG_CONTEXT" = true ]; then CONFIG="$CONTEXT_CONFIG"; else CONFIG="$DEFAULT_CONFIG"; fi
fi
[ -f "$CONFIG" ] || { echo "ERROR: Config file not found: $CONFIG" >&2; exit 2; }
CONFIG="$(cd "$(dirname "$CONFIG")" && pwd)/$(basename "$CONFIG")"

# ── Results directory ───────────────────────────────────────────────────────

MODEL_SAFE=$(echo "$MSWEA_MODEL_NAME" | tr '/:<>' '____')
DATE_TAG=$(date +%Y%m%d-%H%M%S)
if [ -z "$RESULTS_DIR" ]; then
    RESULTS_DIR="$RESULTS_ROOT/mini-swe-agent/${MODEL_SAFE}/${DATE_TAG}"
fi

# ── Resolve case list ───────────────────────────────────────────────────────

get_case_list() {
    python3 - "$1" "$REGISTRY" <<'PYTHON'
import json, sys

surface_arg, registry_path = sys.argv[1], sys.argv[2]
with open(registry_path) as f:
    cases = json.load(f)["cases"]
valid = {"tier1", "tier2", "tier3"}
if surface_arg == "all":
    wanted = None
else:
    wanted = set(surface_arg.split(","))
    unknown = wanted - valid
    if unknown:
        print(f"Unknown surface: {', '.join(sorted(unknown))}. Valid: tier1, tier2, tier3, all",
              file=sys.stderr)
        sys.exit(2)
for c in cases:
    if wanted is None or c.get("surface_membership") in wanted:
        print(c["case_id"])
PYTHON
}

if [ -n "$SURFACE" ]; then
    CASE_LIST=$(get_case_list "$SURFACE")
    TOTAL=$(printf '%s\n' "$CASE_LIST" | grep -c . || true)
    LABEL="surface $SURFACE ($TOTAL cases)"
else
    [ -d "$CASES_ROOT/cases/$CASE_NAME" ] || { echo "ERROR: unknown case $CASE_NAME" >&2; exit 2; }
    CASE_LIST="$CASE_NAME"
    TOTAL=1
    LABEL="case $CASE_NAME"
fi

if [ -z "$CASE_LIST" ] || [ "$TOTAL" -eq 0 ]; then
    echo "ERROR: No cases found" >&2
    exit 2
fi

# ── Agent prompt ────────────────────────────────────────────────────────────

# The prompt is a one-line task description. The full system prompt with the
# no-search constraints is in the YAML config.
AGENT_PROMPT="Read SYMPTOM.md and fix the bug described in it. Do not search for the GitHub issue or known fix."
if [ "$DEBUG_CONTEXT" = true ]; then
    AGENT_PROMPT="Read SYMPTOM.md and fix the bug described in it. The context/ folder contains debug context gathered by a developer. Do not search for the GitHub issue or known fix."
    export BENCH_CONTEXT=1
fi

# Export the host-network flag so bench.sh picks it up
if [ "$HOST_NETWORK" = true ]; then
    export BENCH_HOST_NETWORK=1
fi

# ── Banner ──────────────────────────────────────────────────────────────────

echo "=== DDBench Agent Runner ==="
echo "  Agent:     mini-swe-agent"
echo "  Model:     $MSWEA_MODEL_NAME"
echo "  Config:    $CONFIG"
echo "  Target:    $LABEL"
echo "  Timeout:   ${AGENT_TIMEOUT}s per case (scoring: ${SCORE_TIMEOUT}s)"
echo "  Results:   $RESULTS_DIR"
echo "  Host net:  $HOST_NETWORK"
echo "  Context:   $DEBUG_CONTEXT"
echo "  Dry run:   $DRY_RUN"
echo ""
echo "  Trajectories are saved per case at: $RESULTS_DIR/<case>/trajectory.traj.json"
echo "  Monitor live:  tail -f $RESULTS_DIR/<case>/trajectory.traj.json"
echo ""

if [ "$DRY_RUN" = false ]; then
    mkdir -p "$RESULTS_DIR"
    python3 - "$RESULTS_DIR/run_metadata.json" "$MSWEA_MODEL_NAME" "$CONFIG" \
        "$([ "$DEBUG_CONTEXT" = true ] && echo context || echo repo-only)" "${SURFACE:-single}" \
        "$AGENT_TIMEOUT" "$TOTAL" <<'PYTHON'
import json, sys
from datetime import datetime, timezone
out, model, config, condition, surface, timeout, total = sys.argv[1:8]
with open(out, "w") as f:
    json.dump({"agent": "mini-swe-agent", "model": model, "config": config,
               "condition": condition, "surface": surface,
               "timeout_seconds": int(timeout), "cases": int(total),
               "started_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")},
              f, indent=2)
PYTHON
fi

# ── Run loop ────────────────────────────────────────────────────────────────

PASSED=0
FAILED=0
ERRORS=0
COUNT=0

result_of() {  # <result.json> -> PASS|FAIL|ERROR|UNKNOWN
    python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("result","UNKNOWN"))' "$1" 2>/dev/null \
        || echo UNKNOWN
}

for case_name in $CASE_LIST; do
    CURRENT_CASE="$case_name"
    COUNT=$((COUNT + 1))
    echo ""
    echo "[$COUNT/$TOTAL] $case_name"
    echo "  $(date +%H:%M:%S)"

    if [ "$DRY_RUN" = true ]; then
        [ "$SKIP_SETUP" = true ] || echo "  [dry-run] bench.sh setup $case_name"
        echo "  [dry-run] bench.sh reset $case_name"
        echo "  [dry-run] bench.sh agent $case_name --addon mini-swe-agent --config $CONFIG --output-dir $RESULTS_DIR/$case_name --prompt \"$AGENT_PROMPT\"$([ "$DEBUG_CONTEXT" = true ] && echo ' (BENCH_CONTEXT=1)')"
        echo "  [dry-run] harness/score_case.sh $case_name $RESULTS_DIR --timeout $SCORE_TIMEOUT$([ "$NO_RESET" = true ] && echo ' --no-reset')"
        continue
    fi

    # Step 1: Setup (if needed)
    if [ "$SKIP_SETUP" = false ]; then
        echo "  Setting up ..."
        if ! bash "$BENCH" setup "$case_name" >"$RESULTS_DIR/${case_name}_setup.log" 2>&1; then
            echo "  ERROR: setup failed (see ${case_name}_setup.log)"
            ERRORS=$((ERRORS + 1))
            continue
        fi
        [ "$INTERRUPTED" = true ] && break
    fi

    # Step 2: Run the agent with a timeout
    echo "  Running mini-swe-agent (model=$MSWEA_MODEL_NAME, timeout=${AGENT_TIMEOUT}s) ..."
    CASE_OUTPUT_DIR="$RESULTS_DIR/$case_name"
    mkdir -p "$CASE_OUTPUT_DIR"
    echo "  Trajectory: $CASE_OUTPUT_DIR/trajectory.traj.json"
    AGENT_START=$(date +%s)

    # Stop any existing container for this case first
    bash "$BENCH" stop "$case_name" >/dev/null 2>&1 || true

    # Start from the pristine buggy worktree: removes leftovers from earlier runs,
    # e.g. a test file injected by an interrupted reproduce.sh.
    if ! bash "$BENCH" reset "$case_name" >"$RESULTS_DIR/${case_name}_prereset.log" 2>&1; then
        echo "  ERROR: pre-agent reset failed (see ${case_name}_prereset.log)"
        ERRORS=$((ERRORS + 1))
        continue
    fi

    # setsid: run bench.sh agent in a NEW SESSION so it is immune to SIGTSTP
    # signals from the controlling terminal's job control.
    # Background + wait: lets the trap handler capture AGENT_PID for cleanup.
    setsid timeout "$AGENT_TIMEOUT" bash "$BENCH" agent "$case_name" \
        --addon mini-swe-agent \
        --config "$CONFIG" \
        --output-dir "$CASE_OUTPUT_DIR" \
        --prompt "$AGENT_PROMPT" \
        >"$RESULTS_DIR/${case_name}_agent.log" 2>&1 &
    AGENT_PID=$!

    wait "$AGENT_PID" 2>/dev/null && AGENT_EXIT=0 || AGENT_EXIT=$?
    AGENT_PID=""    # Clear so cleanup doesn't try to kill a finished process

    if [ "$INTERRUPTED" = true ]; then
        break
    fi

    if [ "$AGENT_EXIT" -eq 0 ]; then
        echo "  Agent completed successfully."
    elif [ "$AGENT_EXIT" -eq 124 ]; then
        echo "  Agent timed out after ${AGENT_TIMEOUT}s."
    else
        echo "  Agent exited with code $AGENT_EXIT."
    fi
    echo "  Agent duration: $(( $(date +%s) - AGENT_START ))s"

    # Stop the container (the agent may have left it running)
    bash "$BENCH" stop "$case_name" >/dev/null 2>&1 || true

    # Step 3: Score (score_case.sh also resets unless --no-reset)
    echo "  Scoring ..."
    SCORE_ARGS=(--timeout "$SCORE_TIMEOUT")
    [ "$NO_RESET" = true ] && SCORE_ARGS+=(--no-reset)
    [ "$AGENT_EXIT" -eq 124 ] && SCORE_ARGS+=(--agent-timeout)

    if bash "$HARNESS_DIR/score_case.sh" "$case_name" "$RESULTS_DIR" "${SCORE_ARGS[@]}" 2>&1 | tail -3; then
        result_file="$RESULTS_DIR/$case_name/result.json"
        if [ -f "$result_file" ]; then
            case "$(result_of "$result_file")" in
                PASS) PASSED=$((PASSED + 1)); echo "  PASS" ;;
                FAIL) FAILED=$((FAILED + 1)); echo "  FAIL" ;;
                *)    ERRORS=$((ERRORS + 1)); echo "  ERROR (oracle/infrastructure; not counted as a model failure)" ;;
            esac
        else
            ERRORS=$((ERRORS + 1))
            echo "  ERROR: no result.json produced"
        fi
    else
        ERRORS=$((ERRORS + 1))
        echo "  ERROR: scoring failed"
    fi

    [ "$INTERRUPTED" = true ] && break
    CURRENT_CASE=""
done

# ── Aggregate ───────────────────────────────────────────────────────────────

if [ "$DRY_RUN" = false ] && [ "$TOTAL" -gt 1 ]; then
    echo ""
    echo "=== Aggregating results ==="
    python3 "$HARNESS_DIR/aggregate_results.py" "$RESULTS_DIR" "$REGISTRY" 2>&1 || \
        echo "WARNING: aggregation failed"
fi

# ── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "=== DDBench Agent Run Complete ==="
echo "  Agent:   mini-swe-agent"
echo "  Model:   $MSWEA_MODEL_NAME"
echo "  Target:  $LABEL"
echo "  Total:   $TOTAL"
if [ "$DRY_RUN" = false ]; then
    echo "  Passed:  $PASSED"
    echo "  Failed:  $FAILED"
    echo "  Errors:  $ERRORS (setup/oracle/infrastructure; excluded from the pass rate)"
    SCORED=$((PASSED + FAILED))
    if [ "$SCORED" -gt 0 ]; then
        echo "  Pass rate: $(python3 -c "print(f'{$PASSED/$SCORED*100:.1f}%')") ($PASSED/$SCORED scored)"
    fi
    echo ""
    echo "  Results: $RESULTS_DIR/"
    [ -f "$RESULTS_DIR/summary.md" ] && echo "  Report:  $RESULTS_DIR/summary.md"
else
    echo ""
    echo "  (dry run: no results produced)"
fi

if [ "$INTERRUPTED" = true ]; then
    echo ""
    echo "  Run was interrupted by user after $COUNT/$TOTAL cases."
    exit 130
fi
