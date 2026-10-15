#!/usr/bin/env bash
# Reproduction and verification script for rabbitmq-12635-qq-snapshot-crash
# Injects a Common Test case into quorum_queue_SUITE (cluster_size_3 group): with
# one member stopped, force a checkpoint and a snapshot on the leader (publish,
# assign to a consumer, purge), then restart the stopped member. It must not
# crash while catching up.
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

SUITE="deps/rabbit/test/quorum_queue_SUITE.erl"
CASE=ddbench_oracle_qq_snapshot
LOG="$RUN_DIR/ct.log"

rebuild_worktree
[ -f "$WORK_DIR/$SUITE" ] || error "$SUITE not found in $WORK_DIR (run setup first)"
cd "$WORK_DIR"

echo "=== Reproducing rabbitmq-12635-qq-snapshot-crash ==="

# Inject into the pristine suite (the worktree's version is restored after), so
# a same-named or stub case in the worktree cannot replace the oracle case.
cp "$SUITE" "$RUN_DIR/suite.saved"
# Common Test logs (written to ./logs and deps/rabbit/logs) and the beam
# compiled from the injected suite must not outlive the run.
drop_ct_artifacts() {
    local d
    for d in logs deps/rabbit/logs; do
        git ls-files --error-unmatch "$d" >/dev/null 2>&1 || rm -rf "$d"
    done
    rm -f deps/rabbit/test/quorum_queue_SUITE.beam
}
cleanup() { cp "$RUN_DIR/suite.saved" "$SUITE"; drop_ct_artifacts; }
trap cleanup EXIT
drop_ct_artifacts
git show HEAD:"$SUITE" > "$SUITE" || error "could not read the pristine $SUITE"
grep -qE 'force_vhost_queues_shrink_member_to_current_member$' "$SUITE" \
    || error "injection anchor not found in $SUITE"
sed -i 's/force_vhost_queues_shrink_member_to_current_member$/force_vhost_queues_shrink_member_to_current_member,\n                                            ddbench_oracle_qq_snapshot/' "$SUITE"
cat >> "$SUITE" << 'TESTEOF'
ddbench_oracle_qq_snapshot(Config) ->
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

echo "Running CT case $CASE (quorum_queue_SUITE, cluster_size_3; starts a 3-node cluster) ..."
make -C deps/rabbit ct-quorum_queue t=cluster_size_3:$CASE > "$LOG" 2>&1
rc=$?
tail -40 "$LOG"
ct_verdict "$WORK_DIR/logs" "$CASE" "$LOG" "$rc" \
    "Bug is fixed — the restarted quorum queue member does not crash after snapshot installation" \
    "Bug is present — the restarted quorum queue member crashed after snapshot installation"
