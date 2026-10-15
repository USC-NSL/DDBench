# Test Output

Obtained by running a master-slave replication test with `repl-namespace-enabled yes` in cluster mode: start master and slave, write initial key, stop slave, update key on master, restart slave, check slave for replicated values.

## Output

```
Step 1: Starting master on port 6666 (cluster mode)...
Waiting for Master on port 6666...
Master is ready.
OK

Step 2: Starting slave on port 6667 (cluster mode + repl-namespace-enabled)...
Waiting for Slave on port 6667...
Slave is ready.
OK

Step 3: Setting up cluster topology...
OK
OK
Waiting for slave replication to be up...
Slave replication is up.

Step 4: Setting k0=v0 on master...
OK
3
Waiting for replication offset sync...
Offsets synced at 5.
Slave GET k0 = 'v0'
Initial replication verified.

Step 5: Stopping slave...

Step 6: Updating keys on master while slave is down...
OK
2
Master SET k0=v1, HSET k2 f0=v0 f1=v1

Step 7: Restarting slave...
Waiting for Slave on port 6667...
Slave is ready.
Waiting for slave replication to be up...
Slave replication is up.
Waiting for replication offset sync...
Offsets synced at 9.

Step 8: Checking slave for replicated keys...
Slave GET k0 = 'v0' (expected 'v1')
Slave HGET k2 f0 = 'v0' (expected 'v0')
Slave HGET k2 f1 = 'v1' (expected 'v1')
```
