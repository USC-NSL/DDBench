package raft

import (
	"context"
	"fmt"
	"testing"
	"time"
)

// TestPreVoteLeaderSpamBlocksElection verifies that granting pre-vote
// requests does NOT refresh the "last contact with leader" timestamp.
//
// Bug (hashicorp/raft#609): When a follower grants a pre-vote request,
// it calls setLastContact(), treating the pre-vote as evidence of a
// healthy leader. If pre-vote requests arrive frequently enough, followers
// never time out their election timer and can never transition to
// candidate state. This is a liveness violation: the cluster cannot elect
// a new leader even after the real leader stops sending heartbeats.
//
// Detection strategy:
//   - Create a 3-node cluster with pre-vote enabled (the default)
//   - Continuously spam followers with pre-vote requests
//   - Block real heartbeats from the leader to the followers
//   - Attempt to detect a new leader among the followers
//   - On buggy code: pre-votes refresh last-contact, followers never
//     time out, no new leader is elected -> test FAILS
//   - On fixed code: pre-votes don't refresh last-contact, followers
//     time out normally, a new leader is elected -> test PASSES
//
// This test must live in the raft package because it accesses internal
// APIs (localID, localAddr, getRPCHeader, getCurrentTerm, getLastIndex,
// processHeartbeat) and requires the NetworkTransport heartbeat fast-path.
func TestDDBenchOraclePreVoteSpamElection(t *testing.T) {
	conf := DefaultConfig()
	conf.LocalID = ServerID("first")
	conf.HeartbeatTimeout = 50 * time.Millisecond
	conf.ElectionTimeout = 50 * time.Millisecond
	conf.LeaderLeaseTimeout = 50 * time.Millisecond
	conf.CommitTimeout = 5 * time.Second
	conf.SnapshotThreshold = 100
	conf.TrailingLogs = 10

	// Create a single node and bootstrap it as leader
	leader := MakeRaft(t, conf, true)
	NoErr(WaitFor(leader, Leader), t)

	// Join 2 followers
	var followers []*RaftEnv
	for i := 0; i < 2; i++ {
		conf.LocalID = ServerID(fmt.Sprintf("next-batch-%d", i))
		env := MakeRaft(t, conf, false)
		addr := env.trans.LocalAddr()
		NoErr(WaitFuture(leader.raft.AddVoter(conf.LocalID, addr, 0, 0)), t)
		followers = append(followers, env)
	}

	// Wait for a stable leader
	_, err := WaitForAny(Leader, append([]*RaftEnv{leader}, followers...))
	NoErr(err, t)

	CheckConsistent(append([]*RaftEnv{leader}, followers...), t)

	leaderT := leader.raft.trans

	// Spam all the followers with pre-vote requests from the leader.
	// These requests should be granted as long as the leader hasn't changed.
	// On buggy code, granting them refreshes last-contact, preventing timeout.
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go func() {
		for {
			ticker := time.NewTicker(conf.HeartbeatTimeout / 2)
			for _, f := range followers {
				rsp := RequestPreVoteResponse{}
				reqPreVote := RequestPreVoteRequest{
					RPCHeader:    leader.raft.getRPCHeader(),
					Term:         leader.raft.getCurrentTerm() + 1,
					LastLogIndex: leader.raft.getLastIndex(),
					LastLogTerm:  leader.raft.getCurrentTerm(),
				}
				// We don't need to check the error here because when leader changes
				// it will start failing with "rejecting pre-vote request since we have a leader"
				_ = leaderT.(WithPreVote).RequestPreVote(f.raft.localID, f.raft.localAddr, &reqPreVote, &rsp)
			}
			select {
			case <-ticker.C:
			case <-ctx.Done():
				return
			}
		}
	}()
	time.Sleep(time.Second)

	// For all followers, ignore heartbeats from the current leader so they
	// can transition to candidate state. The purpose of this test is to
	// verify that spamming nodes with pre-votes doesn't prevent them from
	// transitioning to candidates.
	for _, f := range followers {
		// Copy f to avoid data race
		f1 := f
		f1.trans.SetHeartbeatHandler(func(rpc RPC) {
			if a, ok := rpc.Command.(*AppendEntriesRequest); ok {
				if ServerID(a.GetRPCHeader().ID) == leader.raft.localID {
					resp := &AppendEntriesResponse{
						RPCHeader:      f1.raft.getRPCHeader(),
						Term:           f1.raft.getCurrentTerm(),
						LastLog:        f1.raft.getLastIndex(),
						Success:        false,
						NoRetryBackoff: false,
					}
					rpc.Respond(resp, nil)
				} else {
					f.raft.processHeartbeat(rpc)
				}
			}
		})
	}
	time.Sleep(1 * time.Second)

	// A new leader should be elected from the followers.
	// On buggy code this will fail because pre-votes keep refreshing
	// last-contact, preventing election timeout.
	_, err = WaitForAny(Leader, followers)
	NoErr(err, t)
}
