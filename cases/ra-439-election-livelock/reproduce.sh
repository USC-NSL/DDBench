#!/usr/bin/env bash
# Reproduce script for ra-439-election-livelock
# Tests that a Raft candidate correctly handles pre_vote_rpc from a peer
# with a higher log index (rather than ignoring it), which would otherwise
# cause an election livelock.
# ── Docker mode (preferred) ──
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
    exec "$REPO_ROOT/bench.sh" reproduce "$CASE_NAME"
fi
# ── Host fallback (no Docker) ──
set -euo pipefail

WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/ra-439-election-livelock"
SUITE="$WORK_DIR/test/ra_server_SUITE.erl"
RESULT_LOG="/tmp/ra_439_ct_output.txt"

echo "=== Reproducing ra-439-election-livelock ==="

cd "$WORK_DIR"

# Reset to buggy state (undo any previous inject)
git checkout -- test/ra_server_SUITE.erl 2>/dev/null || true

# Inject the candidate_receives_pre_vote test case into ra_server_SUITE.erl.
# The test was added in the fix PR and verifies that handle_candidate/2 correctly
# processes a #pre_vote_rpc{} with a log index equal to or lower than the
# candidate, instead of silently dropping it.
python3 - <<'PYEOF'
import sys

with open('test/ra_server_SUITE.erl', 'r') as f:
    content = f.read()

if 'candidate_receives_pre_vote' in content:
    print("Test already present")
    sys.exit(0)

# 1. Add test name to all() list after leader_receives_pre_vote
content = content.replace(
    '     leader_receives_pre_vote,',
    '     candidate_receives_pre_vote,\n     leader_receives_pre_vote,'
)

# 2. Insert the test function body before leader_receives_pre_vote/1
test_fn = '''
candidate_receives_pre_vote(_Config) ->
    Token = make_ref(),
    State = (base_state(5, candidate_receives_pre_vote))#{votes => 1},
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

'''

content = content.replace(
    'leader_receives_pre_vote(_Config) ->',
    test_fn + 'leader_receives_pre_vote(_Config) ->'
)

with open('test/ra_server_SUITE.erl', 'w') as f:
    f.write(content)

print("Test injected into ra_server_SUITE.erl")
PYEOF

# Remove stale broken dep directories that may have been partially created.
# eunit_formatters and inet_tcp_proxy use abandoned 'master' branches and are
# not needed for our unit test. TEST_DEPS override avoids re-fetching them.
rm -rf deps/eunit_formatters deps/inet_tcp_proxy 2>/dev/null || true

# Run the specific test case, restricting TEST_DEPS to only what is needed
echo "Running candidate_receives_pre_vote test..."
if make ct CT_SUITES=ra_server CT_OPTS="-case candidate_receives_pre_vote" TEST_DEPS="proper meck" 2>&1 | tee "$RESULT_LOG"; then
    CT_EXIT=0
else
    CT_EXIT=1
fi

# Parse CT output for pass/fail
if grep -qE "1 ok|PASSED|All [0-9]+ test cases passed" "$RESULT_LOG" && ! grep -qE "^1 failed|FAILED" "$RESULT_LOG"; then
    echo ""
    echo "PASS: Bug is fixed"
    exit 0
else
    echo ""
    echo "FAIL: Bug is present — candidate silently drops pre_vote_rpc instead of replying"
    exit 1
fi
