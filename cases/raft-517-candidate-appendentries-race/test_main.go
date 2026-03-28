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
	nodes := make([]*raft.Raft, 3)
	transports := make([]*raft.InmemTransport, 3)

	for i := 0; i < 3; i++ {
		nodes[i], transports[i] = makeRaft(fmt.Sprintf("node%d", i))
	}

	for i := 0; i < 3; i++ {
		for j := 0; j < 3; j++ {
			if i != j {
				transports[i].Connect(transports[j].LocalAddr(), transports[j])
			}
		}
	}

	servers := make([]raft.Server, 3)
	for i := 0; i < 3; i++ {
		servers[i] = raft.Server{
			ID:      raft.ServerID(fmt.Sprintf("node%d", i)),
			Address: transports[i].LocalAddr(),
		}
	}
	nodes[0].BootstrapCluster(raft.Configuration{Servers: servers})

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

	for i := 0; i < 5; i++ {
		f := nodes[leaderIdx].Apply([]byte(fmt.Sprintf("entry-%d", i)), 5*time.Second)
		if err := f.Error(); err != nil {
			fmt.Printf("Apply error: %v\n", err)
		}
	}

	var mu sync.Mutex
	_ = mu

	for round := 0; round < 20; round++ {
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

		f := nodes[currentLeader].LeadershipTransfer()
		_ = f.Error()

		time.Sleep(300 * time.Millisecond)

		for i := 0; i < 3; i++ {
			if nodes[i].State() == raft.Leader {
				go func(idx, r int) {
					for j := 0; j < 3; j++ {
						nodes[idx].Apply([]byte(fmt.Sprintf("round%d-entry%d", r, j)), 2*time.Second)
					}
				}(i, round)
				break
			}
		}
	}

	for i := 0; i < 3; i++ {
		nodes[i].Shutdown()
	}
	fmt.Println("Test completed")
	os.Exit(0)
}
