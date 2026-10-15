# Code Investigation

## What was searched
The symptom describes ACL token/policy/role replication stopping when a server loses leadership and not resuming when the same server regains it shortly afterwards. The leader code starts and stops these replication loops by name through the routine manager in `lib/routine/`, so read how that manager tracks routines.

## What was found
```
$ grep -n "ReplicationRoutineName" agent/consul/leader.go
627:	if s.leaderRoutineManager.IsRunning(aclPolicyReplicationRoutineName) {
632:	s.leaderRoutineManager.Start(ctx, aclPolicyReplicationRoutineName, s.runACLPolicyReplicator)
633:	s.leaderRoutineManager.Start(ctx, aclRoleReplicationRoutineName, s.runACLRoleReplicator)
636:		s.leaderRoutineManager.Start(ctx, aclTokenReplicationRoutineName, s.runACLTokenReplicator)
741:	s.leaderRoutineManager.Stop(aclPolicyReplicationRoutineName)
742:	s.leaderRoutineManager.Stop(aclRoleReplicationRoutineName)
743:	s.leaderRoutineManager.Stop(aclTokenReplicationRoutineName)
752:	s.leaderRoutineManager.Start(ctx, configReplicationRoutineName, s.configReplicator.Run)
757:	s.leaderRoutineManager.Stop(configReplicationRoutineName)
771:	s.leaderRoutineManager.Start(ctx, federationStateReplicationRoutineName, s.federationStateReplicator.Run)
776:	s.leaderRoutineManager.Stop(federationStateReplicationRoutineName)
```

```
$ cat -n lib/routine/routine.go | sed -n '13,136p'
    13	type routineTracker struct {
    14		cancel    context.CancelFunc
    15		stoppedCh chan struct{} // closed when no longer running
    16	}
    17	
    18	func (r *routineTracker) running() bool {
    19		select {
    20		case <-r.stoppedCh:
    21			return false
    22		default:
    23			return true
    24		}
    25	}
    26	
    27	func (r *routineTracker) wait() {
    28		<-r.stoppedCh
    29	}
    30	
    31	type Manager struct {
    32		lock   sync.RWMutex
    33		logger hclog.Logger
    34	
    35		routines map[string]*routineTracker
    36	}
    37	
    38	func NewManager(logger hclog.Logger) *Manager {
    39		if logger == nil {
    40			logger = hclog.New(&hclog.LoggerOptions{
    41				Output: os.Stderr,
    42			})
    43		}
    44	
    45		return &Manager{
    46			logger:   logger,
    47			routines: make(map[string]*routineTracker),
    48		}
    49	}
    50	
    51	func (m *Manager) IsRunning(name string) bool {
    52		m.lock.Lock()
    53		defer m.lock.Unlock()
    54	
    55		if routine, ok := m.routines[name]; ok {
    56			return routine.running()
    57		}
    58	
    59		return false
    60	}
    61	
    62	func (m *Manager) Start(ctx context.Context, name string, routine Routine) error {
    63		m.lock.Lock()
    64		defer m.lock.Unlock()
    65	
    66		if instance, ok := m.routines[name]; ok && instance.running() {
    67			return nil
    68		}
    69	
    70		if ctx == nil {
    71			ctx = context.Background()
    72		}
    73	
    74		rtCtx, cancel := context.WithCancel(ctx)
    75		instance := &routineTracker{
    76			cancel:    cancel,
    77			stoppedCh: make(chan struct{}),
    78		}
    79	
    80		go m.execute(rtCtx, name, routine, instance.stoppedCh)
    81	
    82		m.routines[name] = instance
    83		m.logger.Info("started routine", "routine", name)
    84		return nil
    85	}
    86	
    87	// execute will run the given routine in the foreground and close the given channel when its done executing
    88	func (m *Manager) execute(ctx context.Context, name string, routine Routine, done chan struct{}) {
    89		defer func() {
    90			close(done)
    91		}()
    92	
    93		err := routine(ctx)
    94		if err != nil && err != context.DeadlineExceeded && err != context.Canceled {
    95			m.logger.Error("routine exited with error",
    96				"routine", name,
    97				"error", err,
    98			)
    99		} else {
   100			m.logger.Debug("stopped routine", "routine", name)
   101		}
   102	}
   103	
   104	func (m *Manager) Stop(name string) <-chan struct{} {
   105		instance := m.stopInstance(name)
   106		if instance == nil {
   107			// Fabricate a closed channel so it won't block forever.
   108			ch := make(chan struct{})
   109			close(ch)
   110			return ch
   111		}
   112	
   113		return instance.stoppedCh
   114	}
   115	
   116	func (m *Manager) stopInstance(name string) *routineTracker {
   117		m.lock.Lock()
   118		defer m.lock.Unlock()
   119	
   120		instance, ok := m.routines[name]
   121		if !ok {
   122			// no running instance
   123			return nil
   124		}
   125	
   126		if !instance.running() {
   127			return instance
   128		}
   129	
   130		m.logger.Debug("stopping routine", "routine", name)
   131		instance.cancel()
   132	
   133		delete(m.routines, name)
   134	
   135		return instance
   136	}
```

## Developer hypothesis
Whether `Start()` launches a routine depends on the per-name state the manager keeps from earlier `Start()`/`Stop()` calls. Worth checking how that bookkeeping behaves when the same routine name is stopped and started again in quick succession, as happens when leadership is lost and regained.
