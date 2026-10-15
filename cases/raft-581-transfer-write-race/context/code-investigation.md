# Code Investigation

## What was searched
The symptom describes the leader still accepting and committing `Apply()` writes right after `LeadershipTransferToServer()` has returned, so the transfer target sometimes loses the election because its log falls behind. Searched for how the leader loop gates writes during a transfer and read the transfer handling in `leaderLoop` and `leadershipTransfer()` (`raft.go`).

## What was found
```
$ grep -n "LeadershipTransferInProgress" raft.go
394:func (r *Raft) setLeadershipTransferInProgress(v bool) {
402:func (r *Raft) getLeadershipTransferInProgress() bool {
645:			if r.getLeadershipTransferInProgress() {
646:				r.logger.Debug(ErrLeadershipTransferInProgress.Error())
647:				future.respond(ErrLeadershipTransferInProgress)
674:			// It may be safe to modify things such that setLeadershipTransferInProgress
678:				defer r.setLeadershipTransferInProgress(false)
721:			r.setLeadershipTransferInProgress(true)
813:			if r.getLeadershipTransferInProgress() {
814:				r.logger.Debug(ErrLeadershipTransferInProgress.Error())
815:				future.respond(ErrLeadershipTransferInProgress)
823:			if r.getLeadershipTransferInProgress() {
824:				r.logger.Debug(ErrLeadershipTransferInProgress.Error())
825:				future.respond(ErrLeadershipTransferInProgress)
833:			if r.getLeadershipTransferInProgress() {
834:				r.logger.Debug(ErrLeadershipTransferInProgress.Error())
835:				future.respond(ErrLeadershipTransferInProgress)
846:			if r.getLeadershipTransferInProgress() {
847:				r.logger.Debug(ErrLeadershipTransferInProgress.Error())
848:				newLog.respond(ErrLeadershipTransferInProgress)
```

```
$ cat -n raft.go | sed -n '643,723p'
   643			case future := <-r.leadershipTransferCh:
   644				r.mainThreadSaturation.working()
   645				if r.getLeadershipTransferInProgress() {
   646					r.logger.Debug(ErrLeadershipTransferInProgress.Error())
   647					future.respond(ErrLeadershipTransferInProgress)
   648					continue
   649				}
   650	
   651				r.logger.Debug("starting leadership transfer", "id", future.ID, "address", future.Address)
   652	
   653				// When we are leaving leaderLoop, we are no longer
   654				// leader, so we should stop transferring.
   655				leftLeaderLoop := make(chan struct{})
   656				defer func() { close(leftLeaderLoop) }()
   657	
   658				stopCh := make(chan struct{})
   659				doneCh := make(chan error, 1)
   660	
   661				// This is intentionally being setup outside of the
   662				// leadershipTransfer function. Because the TimeoutNow
   663				// call is blocking and there is no way to abort that
   664				// in case eg the timer expires.
   665				// The leadershipTransfer function is controlled with
   666				// the stopCh and doneCh.
   667				// No matter how this exits, have this function set
   668				// leadership transfer to false before we return
   669				//
   670				// Note that this leaves a window where callers of
   671				// LeadershipTransfer() and LeadershipTransferToServer()
   672				// may start executing after they get their future but before
   673				// this routine has set leadershipTransferInProgress back to false.
   674				// It may be safe to modify things such that setLeadershipTransferInProgress
   675				// is set to false before calling future.Respond, but that still needs
   676				// to be tested and this situation mirrors what callers already had to deal with.
   677				go func() {
   678					defer r.setLeadershipTransferInProgress(false)
   679					select {
   680					case <-time.After(r.config().ElectionTimeout):
   681						close(stopCh)
   682						err := fmt.Errorf("leadership transfer timeout")
   683						r.logger.Debug(err.Error())
   684						future.respond(err)
   685						<-doneCh
   686					case <-leftLeaderLoop:
   687						close(stopCh)
   688						err := fmt.Errorf("lost leadership during transfer (expected)")
   689						r.logger.Debug(err.Error())
   690						future.respond(nil)
   691						<-doneCh
   692					case err := <-doneCh:
   693						if err != nil {
   694							r.logger.Debug(err.Error())
   695						}
   696						future.respond(err)
   697					}
   698				}()
   699	
   700				// leaderState.replState is accessed here before
   701				// starting leadership transfer asynchronously because
   702				// leaderState is only supposed to be accessed in the
   703				// leaderloop.
   704				id := future.ID
   705				address := future.Address
   706				if id == nil {
   707					s := r.pickServer()
   708					if s != nil {
   709						id = &s.ID
   710						address = &s.Address
   711					} else {
   712						doneCh <- fmt.Errorf("cannot find peer")
   713						continue
   714					}
   715				}
   716				state, ok := r.leaderState.replState[*id]
   717				if !ok {
   718					doneCh <- fmt.Errorf("cannot find replication state for %v", id)
   719					continue
   720				}
   721				r.setLeadershipTransferInProgress(true)
   722				go r.leadershipTransfer(*id, *address, state, stopCh, doneCh)
   723	
```

```
$ cat -n raft.go | sed -n '928,969p'
   928	// leadershipTransfer is doing the heavy lifting for the leadership transfer.
   929	func (r *Raft) leadershipTransfer(id ServerID, address ServerAddress, repl *followerReplication, stopCh chan struct{}, doneCh chan error) {
   930		// make sure we are not already stopped
   931		select {
   932		case <-stopCh:
   933			doneCh <- nil
   934			return
   935		default:
   936		}
   937	
   938		for atomic.LoadUint64(&repl.nextIndex) <= r.getLastIndex() {
   939			err := &deferError{}
   940			err.init()
   941			repl.triggerDeferErrorCh <- err
   942			select {
   943			case err := <-err.errCh:
   944				if err != nil {
   945					doneCh <- err
   946					return
   947				}
   948			case <-stopCh:
   949				doneCh <- nil
   950				return
   951			}
   952		}
   953	
   954		// Step ?: the thesis describes in chap 6.4.1: Using clocks to reduce
   955		// messaging for read-only queries. If this is implemented, the lease
   956		// has to be reset as well, in case leadership is transferred. This
   957		// implementation also has a lease, but it serves another purpose and
   958		// doesn't need to be reset. The lease mechanism in our raft lib, is
   959		// setup in a similar way to the one in the thesis, but in practice
   960		// it's a timer that just tells the leader how often to check
   961		// heartbeats are still coming in.
   962	
   963		// Step 3: send TimeoutNow message to target server.
   964		err := r.trans.TimeoutNow(id, address, &TimeoutNowRequest{RPCHeader: r.getRPCHeader()}, &TimeoutNowResponse{})
   965		if err != nil {
   966			err = fmt.Errorf("failed to make TimeoutNow RPC to %v: %v", id, err)
   967		}
   968		doneCh <- err
   969	}
```

## Developer hypothesis
Writes and other leader operations are refused only while the leader considers a transfer to be in progress. Worth checking how the lifetime of that in-progress state lines up with the transfer as experienced by the target and the rest of the cluster.
