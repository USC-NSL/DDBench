#!/usr/bin/env bash
# Reproduction and verification script for nats-7718-subscription-leak
# Extracts the test from the fix commit, runs it on the buggy version, and reports PASS/FAIL.
# ── Docker mode (preferred) ──
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
    exec "$REPO_ROOT/bench.sh" reproduce "$CASE_NAME"
fi
# ── Host fallback (no Docker) ──
set -uo pipefail

WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/nats-7718-subscription-leak"
TEST_FILE="server/jetstream_cluster_3_test.go"
TEST_NAME="TestJetStreamClusterLeakedSubsWithStreamImportOverlappingJetStreamSubs"

export PATH=$PATH:/usr/local/go/bin

# ── Rebuild if source changed ──
[ -f "$WORK_DIR/REBUILD.sh" ] && bash "$WORK_DIR/REBUILD.sh"

# Verify setup
if [ ! -f "$WORK_DIR/nats-server" ]; then
    echo "ERROR: Binary not found at $WORK_DIR/nats-server. Run ./setup.sh first."
    exit 1
fi

cd "$WORK_DIR"

echo "=== Reproducing nats-7718-subscription-leak ==="

cleanup() {
    [ -f "${TEST_FILE}.bak" ] && mv "${TEST_FILE}.bak" "$TEST_FILE"
}
trap cleanup EXIT

# Back up the original test file
cp "$TEST_FILE" "${TEST_FILE}.bak"

# Inline the behavioral test function.
# Verifies that subscription counts remain stable across repeated
# stream/consumer create-destroy cycles with overlapping imports.
# On buggy code: subscriptions leak → counts diverge → test FAILS
# On fixed code: proper cleanup → counts stable → test PASSES
if ! grep -q "func ${TEST_NAME}" "$TEST_FILE"; then
cat >> "$TEST_FILE" << 'TESTEOF'

func TestJetStreamClusterLeakedSubsWithStreamImportOverlappingJetStreamSubs(t *testing.T) {
	tmpl := `
	listen: 127.0.0.1:-1
	server_name: %s
	jetstream: {max_mem_store: 2GB, max_file_store: 2GB, store_dir: '%s'}

	leaf {
		listen: 127.0.0.1:-1
	}

	cluster {
		name: %s
		listen: 127.0.0.1:%d
		routes = [%s]
	}

	accounts {
	  ACC: {
		jetstream: enabled
		users: [{user: acc, password: acc}]
		imports: [{stream: {account: zone, subject: ">"}}]
	  }
	  zone: {
		jetstream: enabled
		users: [{user: zone, password: zone}]
		exports: [{stream: ">"}]
	  }
	}
	no_auth_user: acc
`
	c := createJetStreamClusterWithTemplate(t, tmpl, "R3S", 3)
	defer c.shutdown()

	nc, js := jsClientConnect(t, c.randomServer())
	defer nc.Close()

	checkExpectedSubs := func(expected uint32) (actual uint32) {
		t.Helper()
		checkFor(t, 2*time.Second, 100*time.Millisecond, func() error {
			e := expected
			for _, s := range c.servers {
				subs := s.NumSubscriptions()
				if e == 0 {
					e = subs
				} else if e != subs {
					return fmt.Errorf("expected %d subs, got %d", e, subs)
				}
			}
			actual = e
			return nil
		})
		return actual
	}

	var baseline, sc, cc uint32

	for range 3 {
		initial := checkExpectedSubs(0)

		if baseline != 0 {
			require_Equal(t, baseline, initial)
		}

		_, err := js.AddStream(&nats.StreamConfig{
			Name:     "TEST",
			Subjects: []string{"foo"},
			Replicas: 1,
			Storage:  nats.FileStorage,
		})
		require_NoError(t, err)
		sl := c.streamLeader("ACC", "TEST")
		require_NotNil(t, sl)
		afterStreamCreate := checkExpectedSubs(sl.NumSubscriptions())
		if sc == 0 {
			sc = afterStreamCreate
		}
		require_Equal(t, sc, afterStreamCreate)

		_, err = js.AddConsumer("TEST", &nats.ConsumerConfig{Durable: "CONSUMER"})
		require_NoError(t, err)
		afterConsumerCreate := checkExpectedSubs(sl.NumSubscriptions())
		if cc == 0 {
			cc = afterConsumerCreate
		}
		require_Equal(t, cc, afterConsumerCreate)

		require_NoError(t, js.DeleteConsumer("TEST", "CONSUMER"))
		afterConsumerDelete := checkExpectedSubs(sl.NumSubscriptions())
		require_Equal(t, afterStreamCreate, afterConsumerDelete)

		require_NoError(t, js.DeleteStream("TEST"))
		afterStreamDelete := checkExpectedSubs(sl.NumSubscriptions())
		if baseline == 0 {
			baseline = afterStreamDelete
		}
		require_Equal(t, baseline, afterStreamDelete)
	}
}
TESTEOF
fi

# Run the test
echo "Running test $TEST_NAME..."
TEST_OUTPUT=$(go test -v -run "$TEST_NAME" -count=1 -timeout 120s ./server/ 2>&1) || true
TEST_EXIT=$?

echo "$TEST_OUTPUT" | tail -20

# Restore original file
mv "${TEST_FILE}.bak" "$TEST_FILE"

echo ""
if echo "$TEST_OUTPUT" | grep -q "^--- PASS:"; then
    echo "PASS: Bug is fixed — $TEST_NAME passed"
    exit 0
else
    echo "FAIL: Bug is present — $TEST_NAME failed"
    exit 1
fi
