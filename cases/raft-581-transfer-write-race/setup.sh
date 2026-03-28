#!/usr/bin/env bash
# Setup script for raft-581-transfer-write-race
# Clones the repository, checks out the buggy commit, creates and builds test program.
# ── Docker mode (preferred) ──
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
    exec "$REPO_ROOT/bench.sh" setup "$CASE_NAME"
fi
# ── Host fallback (no Docker) ──
set -euo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/raft-581-transfer-write-race"
BUGGY_COMMIT="62eaa1c192d4c09c90caa5e227177eb9205a6267~1"
REPO_URL="https://github.com/hashicorp/raft.git"
RAFT_DIR="$WORK_DIR/raft"
TEST_DIR="$WORK_DIR/test"
export PATH="$PATH:/usr/local/go/bin"

echo "=== Setting up raft-581-transfer-write-race ==="

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
	"errors"
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

func makeRaft(id string) (*raft.Raft, *raft.InmemTransport) {
	config := raft.DefaultConfig()
	config.LocalID = raft.ServerID(id)
	config.HeartbeatTimeout = 500 * time.Millisecond
	config.ElectionTimeout = 500 * time.Millisecond
	config.LeaderLeaseTimeout = 250 * time.Millisecond
	config.CommitTimeout = 100 * time.Millisecond
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

func findLeader(nodes []*raft.Raft) int {
	for i, n := range nodes {
		if n.State() == raft.Leader {
			return i
		}
	}
	return -1
}

func main() {
	numNodes := 7
	nodes := make([]*raft.Raft, numNodes)
	transports := make([]*raft.InmemTransport, numNodes)

	for i := 0; i < numNodes; i++ {
		nodes[i], transports[i] = makeRaft(fmt.Sprintf("node%d", i))
	}

	// Connect all transports
	for i := 0; i < numNodes; i++ {
		for j := 0; j < numNodes; j++ {
			if i != j {
				transports[i].Connect(transports[j].LocalAddr(), transports[j])
			}
		}
	}

	// Bootstrap cluster
	servers := make([]raft.Server, numNodes)
	for i := 0; i < numNodes; i++ {
		servers[i] = raft.Server{
			ID:      raft.ServerID(fmt.Sprintf("node%d", i)),
			Address: transports[i].LocalAddr(),
		}
	}
	config := raft.Configuration{Servers: servers}
	nodes[0].BootstrapCluster(config)

	// Wait for a leader
	deadline := time.Now().Add(15 * time.Second)
	for time.Now().Before(deadline) {
		if findLeader(nodes) >= 0 {
			goto leaderFound
		}
		time.Sleep(50 * time.Millisecond)
	}
	fmt.Println("ERROR: No leader elected within timeout")
	os.Exit(2)

leaderFound:
	leaderIdx := findLeader(nodes)
	fmt.Printf("Leader is node%d\n", leaderIdx)

	// Start concurrent writes in background
	doneCh := make(chan struct{})
	var writerErr error
	var wg sync.WaitGroup
	var writes int
	wg.Add(1)
	leader := nodes[leaderIdx]
	go func() {
		defer wg.Done()
		for {
			select {
			case <-doneCh:
				return
			default:
				future := leader.Apply([]byte("test"), 0)
				err := future.Error()
				switch {
				case err == nil:
					writes++
				case errors.Is(err, raft.ErrNotLeader):
					// Find new leader
					for _, n := range nodes {
						if n.State() == raft.Leader {
							leader = n
							break
						}
					}
				case errors.Is(err, raft.ErrLeadershipTransferInProgress):
					continue
				case errors.Is(err, raft.ErrLeadershipLost):
					continue
				case errors.Is(err, raft.ErrRaftShutdown):
					return
				default:
					writerErr = err
					return
				}
				time.Sleep(time.Millisecond)
			}
		}
	}()

	// Allow some writes to go through first
	time.Sleep(200 * time.Millisecond)

	// Pick a follower as transfer target
	targetIdx := -1
	for i := 0; i < numNodes; i++ {
		if nodes[i].State() == raft.Follower {
			targetIdx = i
			break
		}
	}
	if targetIdx == -1 {
		fmt.Println("ERROR: No follower found")
		close(doneCh)
		wg.Wait()
		os.Exit(2)
	}

	targetID := raft.ServerID(fmt.Sprintf("node%d", targetIdx))
	targetAddr := transports[targetIdx].LocalAddr()

	// Perform leadership transfer to specific target
	currentLeader := findLeader(nodes)
	if currentLeader == -1 {
		fmt.Println("ERROR: No leader found for transfer")
		close(doneCh)
		wg.Wait()
		os.Exit(2)
	}

	fmt.Printf("Transferring leadership to node%d...\n", targetIdx)
	transferFuture := nodes[currentLeader].LeadershipTransferToServer(targetID, targetAddr)
	transferErr := transferFuture.Error()

	// Stop writer goroutine
	close(doneCh)
	wg.Wait()

	if writerErr != nil {
		fmt.Printf("ERROR: Writer error: %v\n", writerErr)
		for i := 0; i < numNodes; i++ {
			nodes[i].Shutdown()
		}
		os.Exit(2)
	}

	if transferErr != nil {
		fmt.Printf("TRANSFER_FAILED: %v\n", transferErr)
		for i := 0; i < numNodes; i++ {
			nodes[i].Shutdown()
		}
		os.Exit(1)
	}

	// Wait briefly for leadership to stabilize
	time.Sleep(500 * time.Millisecond)

	// Check who the leader is now
	newLeaderIdx := findLeader(nodes)
	if newLeaderIdx == -1 {
		// Wait longer
		time.Sleep(2 * time.Second)
		newLeaderIdx = findLeader(nodes)
	}

	// Shutdown all nodes
	for i := 0; i < numNodes; i++ {
		nodes[i].Shutdown()
	}

	if newLeaderIdx == targetIdx {
		fmt.Printf("TRANSFER_OK: Leadership transferred to node%d (writes: %d)\n", targetIdx, writes)
		os.Exit(0)
	} else if newLeaderIdx == -1 {
		fmt.Printf("TRANSFER_FAILED: No leader elected after transfer (writes: %d)\n", writes)
		os.Exit(1)
	} else {
		fmt.Printf("TRANSFER_FAILED: Leadership went to node%d instead of node%d (writes: %d)\n", newLeaderIdx, targetIdx, writes)
		os.Exit(1)
	}
}
GOEOF

# Create go.mod
cd "$TEST_DIR"
cat > go.mod <<MODEOF
module raft-transfer-test

go 1.21
MODEOF

go mod edit -replace "github.com/hashicorp/raft=$RAFT_DIR"
go mod tidy

# Build test binary
echo "Building test binary..."
go build -o "$TEST_DIR/raft-transfer-test" .

echo ""
echo "=== Setup complete ==="
echo "Binary: $TEST_DIR/raft-transfer-test"
