#!/usr/bin/env bash
# Setup script for raft-517-candidate-appendentries-race
# Clones the repository, checks out the buggy commit, creates a Go test
# program that triggers the data race, and builds with -race.
# ── Docker mode (preferred) ──
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
    exec "$REPO_ROOT/bench.sh" setup "$CASE_NAME"
fi
# ── Host fallback (no Docker) ──
set -euo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/raft-517-candidate-appendentries-race"
BUGGY_COMMIT="49bd61b66666fa76cb23fa81897e350f6e9b75de~1"
REPO_URL="https://github.com/hashicorp/raft.git"
RAFT_DIR="$WORK_DIR/raft"
TEST_DIR="$WORK_DIR/test"
export PATH="$PATH:/usr/local/go/bin"

echo "=== Setting up raft-517-candidate-appendentries-race ==="

# Install dependencies
echo "Installing build dependencies..."
sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y git golang-go

# Check prerequisites
for cmd in git go; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: $cmd is required but not installed."
        exit 1
    fi
done

# Clone raft
if [ ! -d "$RAFT_DIR" ]; then
    echo "Cloning repository..."
    mkdir -p "$WORK_DIR"
    git clone "$REPO_URL" "$RAFT_DIR"
fi

cd "$RAFT_DIR"

# Checkout buggy commit
echo "Checking out buggy commit..."
git checkout $BUGGY_COMMIT 2>/dev/null || git checkout $(git rev-parse $BUGGY_COMMIT)

# Create test program
echo "Creating test program..."
mkdir -p "$TEST_DIR"
cat > "$TEST_DIR/main.go" <<'GOEOF'
package main

import (
	"fmt"
	"io"
	"log"
	"os"
	"sync"
	"time"

	"github.com/hashicorp/raft"
)

// Minimal FSM implementation
type MockFSM struct{}

func (m *MockFSM) Apply(l *raft.Log) interface{} { return nil }
func (m *MockFSM) Snapshot() (raft.FSMSnapshot, error) {
	return &MockSnapshot{}, nil
}
func (m *MockFSM) Restore(r io.ReadCloser) error { return nil }

type MockSnapshot struct{}

func (m *MockSnapshot) Persist(sink raft.SnapshotSink) error {
	sink.Write([]byte("snapshot"))
	return sink.Close()
}
func (m *MockSnapshot) Release() {}

func makeRaft(id string, peers []raft.Server) (*raft.Raft, *raft.InmemTransport) {
	config := raft.DefaultConfig()
	config.LocalID = raft.ServerID(id)
	config.HeartbeatTimeout = 200 * time.Millisecond
	config.ElectionTimeout = 200 * time.Millisecond
	config.LeaderLeaseTimeout = 100 * time.Millisecond
	config.CommitTimeout = 50 * time.Millisecond
	config.LogOutput = io.Discard

	store := raft.NewInmemStore()
	snapStore := raft.NewInmemSnapshotStore()
	_, transport := raft.NewInmemTransport("")

	r, err := raft.NewRaft(config, &MockFSM{}, store, store, snapStore, transport)
	if err != nil {
		log.Fatalf("Failed to create raft node %s: %v", id, err)
	}

	return r, transport
}

func main() {
	// Create 3 nodes
	nodes := make([]*raft.Raft, 3)
	transports := make([]*raft.InmemTransport, 3)

	for i := 0; i < 3; i++ {
		nodes[i], transports[i] = makeRaft(fmt.Sprintf("node%d", i), nil)
	}

	// Connect transports
	for i := 0; i < 3; i++ {
		for j := 0; j < 3; j++ {
			if i != j {
				transports[i].Connect(transports[j].LocalAddr(), transports[j])
			}
		}
	}

	// Bootstrap cluster
	servers := make([]raft.Server, 3)
	for i := 0; i < 3; i++ {
		servers[i] = raft.Server{
			ID:      raft.ServerID(fmt.Sprintf("node%d", i)),
			Address: transports[i].LocalAddr(),
		}
	}
	config := raft.Configuration{Servers: servers}
	nodes[0].BootstrapCluster(config)

	// Wait for a leader
	var leaderIdx int
	deadline := time.Now().Add(10 * time.Second)
	for time.Now().Before(deadline) {
		for i := 0; i < 3; i++ {
			if nodes[i].State() == raft.Leader {
				leaderIdx = i
				goto leaderFound
			}
		}
		time.Sleep(50 * time.Millisecond)
	}
	fmt.Println("ERROR: No leader elected within timeout")
	os.Exit(2)

leaderFound:
	fmt.Printf("Leader is node%d\n", leaderIdx)

	// Apply some entries
	for i := 0; i < 5; i++ {
		f := nodes[leaderIdx].Apply([]byte(fmt.Sprintf("entry-%d", i)), 5*time.Second)
		if err := f.Error(); err != nil {
			fmt.Printf("Apply error: %v\n", err)
		}
	}

	// Trigger leadership transfers repeatedly to provoke the race
	raceDetected := false
	var mu sync.Mutex

	for round := 0; round < 20; round++ {
		// Find current leader
		currentLeader := -1
		for i := 0; i < 3; i++ {
			if nodes[i].State() == raft.Leader {
				currentLeader = i
				break
			}
		}
		if currentLeader == -1 {
			time.Sleep(500 * time.Millisecond)
			continue
		}

		// Leadership transfer
		f := nodes[currentLeader].LeadershipTransfer()
		err := f.Error()
		if err != nil {
			// Ignore errors; we just want to trigger the race path
			_ = err
		}

		// Brief wait for the transfer to take effect
		time.Sleep(300 * time.Millisecond)

		// Apply entries on the new leader to generate heartbeat traffic
		for i := 0; i < 3; i++ {
			if nodes[i].State() == raft.Leader {
				go func(idx int) {
					for j := 0; j < 3; j++ {
						f := nodes[idx].Apply([]byte(fmt.Sprintf("round%d-entry%d", round, j)), 2*time.Second)
						if f.Error() != nil {
							mu.Lock()
							mu.Unlock()
						}
					}
				}(i)
				break
			}
		}
	}

	// Shutdown all nodes
	for i := 0; i < 3; i++ {
		nodes[i].Shutdown()
	}

	if raceDetected {
		fmt.Println("Race condition detected")
		os.Exit(1)
	}
	fmt.Println("Test completed")
	os.Exit(0)
}
GOEOF

# Create go.mod
cd "$TEST_DIR"
cat > go.mod <<MODEOF
module raft-race-test

go 1.21
MODEOF

go mod edit -replace "github.com/hashicorp/raft=$RAFT_DIR"
go mod tidy

# Build test binary with race detector
echo "Building test binary with -race flag..."
go build -race -o "$TEST_DIR/raft-race-test" .

echo ""
echo "=== Setup complete ==="
echo "Binary: $TEST_DIR/raft-race-test"
