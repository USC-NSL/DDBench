#!/usr/bin/env bash
# Setup script for raft-268-shutdown-deadlock
# Clones the repository, checks out the buggy commit, creates a Go test
# program, and builds the test binary.
set -euo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/raft-268-shutdown-deadlock"
BUGGY_COMMIT="2e997410f28efe8106fc606d21cb655be1b05dee~1"
REPO_URL="https://github.com/hashicorp/raft.git"
RAFT_DIR="$WORK_DIR/raft"
TEST_DIR="$WORK_DIR/test"
export PATH="$PATH:/usr/local/go/bin"

echo "=== Setting up raft-268-shutdown-deadlock ==="

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
	"time"

	"github.com/hashicorp/raft"
)

// Minimal FSM implementation
type MockFSM struct{}

func (m *MockFSM) Apply(l *raft.Log) interface{} { return nil }
func (m *MockFSM) Snapshot() (raft.FSMSnapshot, error) {
	// Simulate a slow snapshot to increase the race window
	time.Sleep(100 * time.Millisecond)
	return &MockSnapshot{}, nil
}
func (m *MockFSM) Restore(r io.ReadCloser) error { return nil }

type MockSnapshot struct{}

func (m *MockSnapshot) Persist(sink raft.SnapshotSink) error {
	sink.Write([]byte("snapshot"))
	return sink.Close()
}
func (m *MockSnapshot) Release() {}

func main() {
	config := raft.DefaultConfig()
	config.LocalID = "node1"
	config.SnapshotThreshold = 1
	config.SnapshotInterval = 50 * time.Millisecond
	config.LogOutput = os.Stderr

	store := raft.NewInmemStore()
	snapStore := raft.NewInmemSnapshotStore()
	transport, err := raft.NewTCPTransport("127.0.0.1:0", nil, 3, 10*time.Second, os.Stderr)
	if err != nil {
		log.Fatal(err)
	}

	r, err := raft.NewRaft(config, &MockFSM{}, store, store, snapStore, transport)
	if err != nil {
		log.Fatal(err)
	}

	// Bootstrap as single-node cluster
	configuration := raft.Configuration{
		Servers: []raft.Server{
			{ID: "node1", Address: transport.LocalAddr()},
		},
	}
	r.BootstrapCluster(configuration)

	// Wait for leader election
	time.Sleep(3 * time.Second)

	// Apply some entries to trigger snapshot threshold
	for i := 0; i < 10; i++ {
		r.Apply([]byte(fmt.Sprintf("entry-%d", i)), 5*time.Second)
	}

	// Now shutdown — this may deadlock if a snapshot is in progress
	fmt.Println("Calling Shutdown()...")
	done := make(chan struct{})
	go func() {
		future := r.Shutdown()
		if err := future.Error(); err != nil {
			fmt.Printf("Shutdown error: %v\n", err)
		}
		close(done)
	}()

	select {
	case <-done:
		fmt.Println("Shutdown completed successfully")
	case <-time.After(15 * time.Second):
		fmt.Println("DEADLOCK: Shutdown() has been blocked for 15 seconds")
		os.Exit(1)
	}
}
GOEOF

# Create go.mod
cd "$TEST_DIR"
cat > go.mod <<MODEOF
module raft-deadlock-test

go 1.21
MODEOF

go mod edit -replace "github.com/hashicorp/raft=$RAFT_DIR"
go mod tidy

# Build test binary
echo "Building test binary..."
go build -o "$TEST_DIR/raft-deadlock-test" .

echo ""
echo "=== Setup complete ==="
echo "Binary: $TEST_DIR/raft-deadlock-test"
