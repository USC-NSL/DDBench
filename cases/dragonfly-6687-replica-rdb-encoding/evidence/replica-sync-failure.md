# Replica RDB Sync Failure

Obtained by starting a Dragonfly master with tiered storage, loading data, starting a replica, and initiating `REPLICAOF` inside the workspace.

```bash
# Terminal 1: Start master with tiered storage
./build-opt/dragonfly --port 6379 --logtostderr --proactor_threads 1 \
    --dbfilename="" --tiered_prefix=/tmp/dragonfly_tiered \
    --tiered_offload_threshold=1.0 --serialization_max_chunk_size=64000 \
    --maxmemory=512mb

# Terminal 2: Load data to trigger tiered offloading
redis-cli -p 6379 DEBUG POPULATE 200000 key 3000
redis-cli -p 6379 DEBUG POPULATE 200 hash 70 RAND TYPE HASH ELEMENTS 900

# Wait ~15 seconds for tiered offloading, then start replica
./build-opt/dragonfly --port 6380 --logtostderr --proactor_threads 1 \
    --dbfilename="" --maxmemory=1024mb

# Terminal 3: Initiate replication
redis-cli -p 6380 REPLICAOF localhost 6379

# Check replication status
redis-cli -p 6380 INFO replication
```

## Output

### INFO REPLICATION (replica)

```
# Replication
role:slave
master_host:localhost
master_port:16687
master_link_status:down
master_last_io_seconds_ago:0
master_sync_in_progress:0
master_replid:14c88b22771acb1ae8c27521be17eb41a46ad580
slave_priority:100
slave_read_only:1
psync_attempts:0
psync_successes:0
```

### Replica log (first sync cycle showing the error)

```
I20260403 20:31:57.371862    19 protocol_client.cc:153] Resolved endpoint localhost:16687 to 127.0.0.1:16687
I20260403 20:31:57.839491    19 replica.cc:659] Started full sync with localhost:16687
E20260403 20:31:57.882428    19 rdb_load.cc:1259] Unknown RDB string encoding 10
W20260403 20:31:57.882637    19 execution_state.cc:93] ReportError: Internal error when loading RDB file 5: Error loading rdb format
W20260403 20:31:57.882677    19 protocol_client.cc:256] Socket error: Internal error when loading RDB file 5: Error loading rdb format in localhost:16687, socket info: State: ESTABLISHED, Local: 127.0.0.1:39926, Remote: 127.0.0.1:16687, Inode: 214475955
W20260403 20:31:57.887634    19 replica.cc:284] Error syncing with localhost:16687 (phase: INITIAL_SYNC): dragonfly.rdbload:5 Internal error when loading RDB file 5, socket state: socket not found in /proc/net/tcp or /proc/net/tcp6
```

### Replica log (retry loop continues indefinitely)

```
E20260403 20:31:58.437793    19 rdb_load.cc:1259] Unknown RDB string encoding 10
E20260403 20:31:58.989403    19 rdb_load.cc:1259] Unknown RDB string encoding 10
E20260403 20:31:59.540521    19 rdb_load.cc:1259] Unknown RDB string encoding 10
E20260403 20:32:00.094399    19 rdb_load.cc:1259] Unknown RDB string encoding 10
E20260403 20:32:00.645301    19 rdb_load.cc:1259] Unknown RDB string encoding 10
E20260403 20:32:01.194929    19 rdb_load.cc:1259] Unknown RDB string encoding 10
E20260403 20:32:01.747828    19 rdb_load.cc:1259] Unknown RDB string encoding 10
E20260403 20:32:02.298092    19 rdb_load.cc:1259] Unknown RDB string encoding 10
E20260403 20:32:02.846648    19 rdb_load.cc:1259] Unknown RDB string encoding 10
E20260403 20:32:03.398554    19 rdb_load.cc:1259] Unknown RDB string encoding 10
E20260403 20:32:03.948035    19 rdb_load.cc:1259] Unknown RDB string encoding 10
E20260403 20:32:04.500097    19 rdb_load.cc:1259] Unknown RDB string encoding 10
E20260403 20:32:05.052882    19 rdb_load.cc:1259] Unknown RDB string encoding 10
E20260403 20:32:05.602527    19 rdb_load.cc:1259] Unknown RDB string encoding 10
E20260403 20:32:06.155411    19 rdb_load.cc:1259] Unknown RDB string encoding 10
E20260403 20:32:06.706276    19 rdb_load.cc:1259] Unknown RDB string encoding 10
E20260403 20:32:07.255468    19 rdb_load.cc:1259] Unknown RDB string encoding 10
E20260403 20:32:07.807484    19 rdb_load.cc:1259] Unknown RDB string encoding 10
E20260403 20:32:08.358528    19 rdb_load.cc:1259] Unknown RDB string encoding 10
E20260403 20:32:08.907989    19 rdb_load.cc:1259] Unknown RDB string encoding 10
```

### Replica log (representative full sync cycle showing connect-error-retry pattern)

```
I20260403 20:32:34.247363    19 protocol_client.cc:153] Resolved endpoint localhost:16687 to 127.0.0.1:16687
I20260403 20:32:34.249608    19 replica.cc:659] Started full sync with localhost:16687
E20260403 20:32:34.293881    19 rdb_load.cc:1259] Unknown RDB string encoding 10
W20260403 20:32:34.294035    19 execution_state.cc:93] ReportError: Internal error when loading RDB file 5: Error loading rdb format
W20260403 20:32:34.294137    19 protocol_client.cc:256] Socket error: Internal error when loading RDB file 5: Error loading rdb format in localhost:16687, socket info: State: ESTABLISHED, Local: 127.0.0.1:39932, Remote: 127.0.0.1:16687, Inode: 214475963
W20260403 20:32:34.301040    19 replica.cc:284] Error syncing with localhost:16687 (phase: INITIAL_SYNC): dragonfly.rdbload:5 Internal error when loading RDB file 5, socket state: State: FIN_WAIT1, Local: 127.0.0.1:39932, Remote: 127.0.0.1:16687, Inode: 214475963
I20260403 20:32:34.805164    19 protocol_client.cc:153] Resolved endpoint localhost:16687 to 127.0.0.1:16687
I20260403 20:32:34.807209    19 replica.cc:659] Started full sync with localhost:16687
E20260403 20:32:34.848076    19 rdb_load.cc:1259] Unknown RDB string encoding 10
W20260403 20:32:34.848258    19 execution_state.cc:93] ReportError: Internal error when loading RDB file 5: Error loading rdb format
W20260403 20:32:34.848349    19 protocol_client.cc:256] Socket error: Internal error when loading RDB file 5: Error loading rdb format in localhost:16687, socket info: State: ESTABLISHED, Local: 127.0.0.1:39950, Remote: 127.0.0.1:16687, Inode: 214475977
W20260403 20:32:34.852624    19 replica.cc:284] Error syncing with localhost:16687 (phase: INITIAL_SYNC): dragonfly.rdbload:5 Internal error when loading RDB file 5, socket state: socket not found in /proc/net/tcp or /proc/net/tcp6
```
