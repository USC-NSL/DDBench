#!/usr/bin/env bash
# Reproduction and verification script for rabbitmq-12635-qq-snapshot-crash
# Injects the gh_12635 test from the fix PR into the buggy codebase and runs it
# via Common Test. The test starts a 3-node RabbitMQ cluster, reproduces the
# Raft snapshot crash scenario, and checks whether the quorum queue member crashes.
# ── Docker mode (preferred) ──
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
    exec "$REPO_ROOT/bench.sh" reproduce "$CASE_NAME"
fi
# ── Host fallback (no Docker) ──
set -uo pipefail

WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/rabbitmq-12635-qq-snapshot-crash"
TEST_SUITE="deps/rabbit/test/quorum_queue_SUITE.erl"
TEST_NAME="gh_12635"

# ── Rebuild if source changed ──
[ -f "$WORK_DIR/REBUILD.sh" ] && bash "$WORK_DIR/REBUILD.sh"

# Verify setup
if [ ! -f "$WORK_DIR/sbin/rabbitmq-server" ] && [ ! -d "$WORK_DIR/deps/rabbit/ebin" ]; then
    echo "ERROR: RabbitMQ not built. Run ./setup.sh first."
    exit 1
fi

cd "$WORK_DIR"

echo "=== Reproducing rabbitmq-12635-qq-snapshot-crash ==="

# Back up the original test file
cp "$TEST_SUITE" "${TEST_SUITE}.bak"

cleanup() {
    [ -f "${TEST_SUITE}.bak" ] && mv "${TEST_SUITE}.bak" "$TEST_SUITE"
}
trap cleanup EXIT

# Inject the gh_12635 test into the cluster_size_3 group if not already present
if ! grep -q "gh_12635" "$TEST_SUITE"; then
    echo "Injecting gh_12635 test case into quorum_queue_SUITE..."

    # Step 1: Add gh_12635 to the cluster_size_3 group list.
    # Insert it after force_vhost_queues_shrink_member_to_current_member.
    sed -i 's/force_vhost_queues_shrink_member_to_current_member$/force_vhost_queues_shrink_member_to_current_member,\n                                            gh_12635/' "$TEST_SUITE"

    # Step 2: Append the test function at the end of the file.
    cat >> "$TEST_SUITE" << 'TESTEOF'

gh_12635(Config) ->
    % https://github.com/rabbitmq/rabbitmq-server/issues/12635
    [Server0, _Server1, Server2] =
        rabbit_ct_broker_helpers:get_node_configs(Config, nodename),

    ok = rabbit_ct_broker_helpers:rpc(Config, 0, application, set_env,
                                      [rabbit, quorum_min_checkpoint_interval, 1]),

    Ch0 = rabbit_ct_client_helpers:open_channel(Config, Server0),
    #'confirm.select_ok'{} = amqp_channel:call(Ch0, #'confirm.select'{}),
    QQ = ?config(queue_name, Config),
    RaName = ra_name(QQ),
    ?assertEqual({'queue.declare_ok', QQ, 0, 0},
                 declare(Ch0, QQ, [{<<"x-queue-type">>, longstr, <<"quorum">>}])),

    %% stop member to simulate slow or down member
    ok = rpc:call(Server2, ra, stop_server, [quorum_queues, {RaName, Server2}]),

    publish_confirm(Ch0, QQ),
    publish_confirm(Ch0, QQ),

    %% force a checkpoint on leader
    ok = rpc:call(Server0, ra, cast_aux_command, [{RaName, Server0}, force_checkpoint]),
    rabbit_ct_helpers:await_condition(
      fun () ->
              {ok, #{log := Log}, _} = rpc:call(Server0, ra, member_overview, [{RaName, Server0}]),
              undefined =/= maps:get(latest_checkpoint_index, Log)
      end),

    %% publish 1 more message
    publish_confirm(Ch0, QQ),

    Ch2 = rabbit_ct_client_helpers:open_channel(Config, Server2),
    %% subscribe then cancel, this will assign the messages against the consumer
    %% but as the member is down they will not be delivered
    qos(Ch2, 100, false),
    subscribe(Ch2, QQ, false),
    rabbit_ct_client_helpers:close_channel(Ch2),
    flush(100),
    %% purge
    #'queue.purge_ok'{} = amqp_channel:call(Ch0, #'queue.purge'{queue = QQ}),

    rabbit_ct_helpers:await_condition(
      fun () ->
              {ok, #{log := Log}, _} = rpc:call(Server0, ra, member_overview, [{RaName, Server0}]),
              undefined =/= maps:get(snapshot_index, Log)
      end),
    %% restart the down member
    ok = rpc:call(Server2, ra, restart_server, [quorum_queues, {RaName, Server2}]),
    Pid2 = rpc:call(Server2, erlang, whereis, [RaName]),
    ?assert(is_pid(Pid2)),
    Ref = erlang:monitor(process, Pid2),
    receive
        {'DOWN',Ref, process,_, _} ->
            ct:fail("unexpected DOWN")
    after 500 ->
              ok
    end,
    flush(1),
    ok.
TESTEOF
fi

echo "Running CT test gh_12635 (quorum_queue_SUITE, cluster_size_3 group)..."
echo "This starts a 3-node RabbitMQ cluster and may take several minutes..."
echo ""

# Run the specific test case via Common Test.
# erlang.mk uses t=group:case for filtering, not CASES=
TEST_OUTPUT=$(make -C deps/rabbit ct-quorum_queue t=cluster_size_3:gh_12635 2>&1)
MAKE_EXIT=$?
echo "$TEST_OUTPUT" | tail -40

echo ""

# Check results -- look for CT pass/fail indicators.
# Priority 1: explicit failure markers in the CT output.
if echo "$TEST_OUTPUT" | grep -qE "Failed:.*[1-9]|FAILED|unexpected DOWN|lists,zipwith|test_case_failed"; then
    echo "FAIL: Bug is present -- quorum queue member crashes after Raft snapshot installation"
    echo "  The lists:zipwith crash occurs in delivery_effect/3 when log returns fewer entries than requested"
    exit 1
fi

# Priority 2: explicit pass markers in the CT output.
if echo "$TEST_OUTPUT" | grep -qE "All [0-9]+ tests passed|[0-9]+ ok, 0 failed"; then
    echo "PASS: Bug is fixed -- quorum queue member does not crash after snapshot installation"
    exit 0
fi

# Priority 3: make exit code. When CT passes, make exits 0; when CT fails, make exits non-zero.
if [ "$MAKE_EXIT" -eq 0 ]; then
    echo "PASS: Bug is fixed -- quorum queue member does not crash after snapshot installation"
    exit 0
else
    echo "FAIL: Bug is present -- test encountered errors (make exited $MAKE_EXIT)"
    exit 1
fi
