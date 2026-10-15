package raft

import (
	"sync/atomic"
	"testing"
	"time"

	hclog "github.com/hashicorp/go-hclog"
)

// TestLeadershipTransferWritesDuringTransfer verifies that the leader
// blocks new Apply() calls while a leadership transfer is in progress.
//
// Bug (hashicorp/raft#581): After sending TimeoutNow to the transfer
// target, the leader clears the leadershipTransferInProgress flag
// immediately upon receiving the TimeoutNow response. This creates a
// window where Apply() succeeds on the old leader, advancing its log
// and causing the transfer target to lose the subsequent election
// because its log is now behind.
//
// Detection strategy: We initiate a leadership transfer under heavy
// concurrent write load and check who actually becomes the new leader.
// On the buggy code, writes during the transfer window advance the
// leader's log, so the designated target often loses the election to
// another node with a more up-to-date log. On the fixed code, writes
// are blocked during the transfer window, so the target reliably wins.
func TestDDBenchOracleWritesDuringTransfer(t *testing.T) {
	conf := inmemConfig(t)
	conf.Logger = hclog.New(&hclog.LoggerOptions{Level: hclog.Error})

	// 7 nodes: more voters means more chances for the target to lose
	// if its log falls behind.
	c := MakeCluster(7, t, conf)
	defer c.Close()

	leader := c.Leader()
	// Warm up: apply initial entries so the cluster is stable.
	for i := 0; i < 5; i++ {
		f := leader.Apply([]byte("warmup"), 5*time.Second)
		if err := f.Error(); err != nil {
			t.Fatalf("warmup apply error: %v", err)
		}
	}

	const rounds = 50
	var transferFailures int64

	for round := 0; round < rounds; round++ {
		leader = c.Leader()
		followers := c.Followers()
		if len(followers) == 0 {
			t.Fatalf("round %d: no followers available", round)
		}
		target := followers[0]

		// Start aggressive concurrent writers BEFORE the transfer to
		// maximise the chance that writes land in the transfer window.
		stopWriters := make(chan struct{})
		for w := 0; w < 16; w++ {
			go func() {
				for {
					select {
					case <-stopWriters:
						return
					default:
					}
					// Fire-and-forget writes with no timeout so they
					// queue up in the leader's apply channel.
					f := leader.Apply([]byte("load"), 0)
					_ = f.Error()
				}
			}()
		}

		// Initiate the transfer while writes are in flight.
		future := leader.LeadershipTransferToServer(target.localID, target.localAddr)
		err := future.Error()
		close(stopWriters)

		if err != nil {
			// Transfer itself reported an error (e.g. timeout).
			// This counts as the bug manifesting — the writes during
			// the transfer window made the target's log stale, so the
			// transfer timed out or failed.
			atomic.AddInt64(&transferFailures, 1)
		} else {
			// Transfer future returned success. Check who is actually
			// the leader now.
			time.Sleep(300 * time.Millisecond)
			newLeader := ""
			for _, r := range c.rafts {
				if r.State() == Leader {
					id := r.localID
					newLeader = string(id)
					break
				}
			}
			if newLeader != string(target.localID) {
				atomic.AddInt64(&transferFailures, 1)
			}
		}

		// Stabilise before next round.
		time.Sleep(300 * time.Millisecond)
	}

	t.Logf("Transfer failures: %d/%d", transferFailures, rounds)

	// On buggy code the transfer target frequently loses the election
	// because concurrent writes advance the old leader's log during the
	// transfer window. Typically 2-6 out of 50 transfers fail.
	//
	// On fixed code the flag blocks writes for ElectionTimeout, so the
	// target's log stays current and it wins reliably. 0 failures are
	// expected.
	//
	// Threshold: >1 failure indicates the bug.
	if transferFailures > 1 {
		t.Fatalf("Bug present: %d/%d leadership transfers failed — "+
			"writes leaked through during transfer, causing the target "+
			"to lose the election", transferFailures, rounds)
	}
}
