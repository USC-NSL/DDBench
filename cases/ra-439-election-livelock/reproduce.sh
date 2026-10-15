#!/usr/bin/env bash
# Reproduction and verification script for ra-439-election-livelock
# Injects a unit test case into ra_server_SUITE: a candidate that receives a
# pre_vote_rpc of the same term must answer it (granting for an up-to-date log,
# denying for a stale one) and step down for a higher term.
#
# Exit codes: 0 = PASS (bug fixed), 1 = FAIL (bug present, or the worktree does
# not build / the code under test does not start), 2 = ERROR (oracle or
# infrastructure problem; the verdict is inconclusive).
# ── Runs only inside the bench.sh reproduce container (BENCH_WORKDIR is set) ──
if [ -z "${BENCH_WORKDIR:-}" ]; then
    CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
    REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    [ -f "$REPO_ROOT/bench.sh" ] && exec bash "$REPO_ROOT/bench.sh" reproduce "$CASE_NAME"
    echo "ERROR: run this oracle with ./bench.sh reproduce $CASE_NAME" >&2
    exit 2
fi
set -uo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$BENCH_WORKDIR"
RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ddbench.XXXXXX")"   # scratch space outside the worktree

pass()  { echo ""; echo "PASS: $*"; exit 0; }
fail()  { echo ""; echo "FAIL: $*"; exit 1; }
error() { echo ""; echo "ERROR: $*"; exit 2; }

# REBUILD.sh is the worktree's designated build entry point.
rebuild_worktree() {
    [ -f "$WORK_DIR/REBUILD.sh" ] || error "REBUILD.sh not found in $WORK_DIR (run setup first)"
    bash "$WORK_DIR/REBUILD.sh" || fail "the worktree does not build (REBUILD.sh exited non-zero)"
}

# ── Common Test verdicts ──
# Decided from Common Test's own suite.log record for the single oracle case
# ("=case <SUITE>:<case>" ... "=result ok"), never from console text.
ct_case_result() {  # <logs-dir> <case> -> pass | fail | skip | norun
    local f r
    f=$(grep -rlE --include=suite.log "^=case +[A-Za-z0-9_]+:$2\$" "$1" 2>/dev/null | head -1)
    [ -n "$f" ] || { echo norun; return; }
    r=$(awk -v c="$2" '$1 == "=case" { cur = ($2 ~ (":" c "$")) } cur && $1 == "=result" { print $2; exit }' "$f")
    case "$r" in
        ok*) echo pass ;;
        failed*) echo fail ;;
        skipped*|auto_skipped*) echo skip ;;
        *) echo norun ;;
    esac
}
ct_verdict() {  # <logs-dir> <case> <console-log> <make-exit> <pass-message> <fail-message>
    local r
    r=$(ct_case_result "$1" "$2")
    echo "Common Test result for $2: $r (make exit $4)"
    case "$r" in
        pass) [ "$4" -eq 0 ] && pass "$5"
              fail "the oracle case passed but the test run failed (make exit $4)" ;;
        fail) fail "$6" ;;
        skip) fail "the oracle case was skipped" ;;
    esac
    if grep -qE 'compile error|syntax error|undefined function|\.erl:[0-9]+:([0-9]+:)? ' "$3"; then
        fail "the oracle case did not run: the worktree or the injected oracle case does not compile"
    fi
    error "the oracle case did not run and no compile error was found (make exit $4)"
}

SUITE="test/ra_server_SUITE.erl"
CASE=ddbench_oracle_candidate_pre_vote
LOG="$RUN_DIR/ct.log"

rebuild_worktree
[ -f "$WORK_DIR/$SUITE" ] || error "$SUITE not found in $WORK_DIR (run setup first)"
cd "$WORK_DIR"

echo "=== Reproducing ra-439-election-livelock ==="

# Inject into the pristine suite (the worktree's version is restored after), so
# nothing in the worktree's copy of the suite can affect the oracle case.
cp "$SUITE" "$RUN_DIR/suite.saved"
# Common Test logs (written to ./logs) and the beam compiled from the injected
# suite must not outlive the run.
drop_ct_artifacts() {
    git ls-files --error-unmatch logs >/dev/null 2>&1 || rm -rf logs
    rm -f test/ra_server_SUITE.beam
}
cleanup() { cp "$RUN_DIR/suite.saved" "$SUITE"; drop_ct_artifacts; }
trap cleanup EXIT
drop_ct_artifacts
git show HEAD:"$SUITE" > "$SUITE" || error "could not read the pristine $SUITE"

cat > "$RUN_DIR/case.erl" << 'ERLEOF'

ddbench_oracle_candidate_pre_vote(_Config) ->
    Token = make_ref(),
    State = (base_state(5, ddbench_oracle_candidate_pre_vote))#{votes => 1},
    PreVoteRpc = #pre_vote_rpc{term = 5, candidate_id = {n1, node()},
                               token = Token,
                               machine_version = 0,
                               last_log_index = 3, last_log_term = 5},
    %% candidate must reply with vote_granted=true for equal log index
    {candidate, #{},
     [{reply, #pre_vote_result{token = Token, vote_granted = true}}]}
        = ra_server:handle_candidate(PreVoteRpc, State),
    %% candidate must reply with vote_granted=false for lower log index
    {candidate, #{},
     [{reply, #pre_vote_result{token = Token, vote_granted = false}}]}
        = ra_server:handle_candidate(PreVoteRpc#pre_vote_rpc{last_log_index = 2}, State),
    %% candidate must abdicate to follower for higher term
    {follower, #{current_term := 6}, _}
        = ra_server:handle_candidate(PreVoteRpc#pre_vote_rpc{term = 6}, State),
    ok.
ERLEOF
grep -q '^     leader_receives_pre_vote,$' "$SUITE" && grep -q '^leader_receives_pre_vote(_Config) ->$' "$SUITE" \
    || error "injection anchors not found in $SUITE"
awk -v casefile="$RUN_DIR/case.erl" '
    $0 == "     leader_receives_pre_vote," { print "     ddbench_oracle_candidate_pre_vote,"; print; next }
    $0 == "leader_receives_pre_vote(_Config) ->" { while ((getline l < casefile) > 0) print l; print ""; print; next }
    { print }' "$SUITE" > "$RUN_DIR/suite.injected" && cp "$RUN_DIR/suite.injected" "$SUITE"

# Stale partially-fetched deps that are not needed for this unit test.
rm -rf deps/eunit_formatters deps/inet_tcp_proxy 2>/dev/null || true

echo "Running $CASE ..."
make ct CT_SUITES=ra_server CT_OPTS="-case $CASE" TEST_DEPS="proper meck" > "$LOG" 2>&1
rc=$?
tail -40 "$LOG"
ct_verdict "$WORK_DIR/logs" "$CASE" "$LOG" "$rc" \
    "Bug is fixed — a candidate answers same-term pre-vote requests" \
    "Bug is present — a candidate does not answer a same-term pre-vote request"
