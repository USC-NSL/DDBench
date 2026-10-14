# Server Logs

Obtained by running `redis-cli -p 6666 INFO replication` on the master (`./build/kvrocks`, `log-dir stdout`) before and after its connected replica stopped consuming the replication stream, with writes continuing on the master, followed by the master's log output.

## Output

```
$ redis-cli -p 6666 INFO replication
# Replication
role:master
connected_slaves:1
slave0:ip=127.0.0.1,port=6667,offset=0,lag=0
master_repl_offset:0

$ redis-cli -p 6666 INFO replication
# Replication
role:master
connected_slaves:1
slave0:ip=127.0.0.1,port=6667,offset=0,lag=2000
master_repl_offset:2000
$ cat master.log
[2026-10-14T08:29:29.563040+00:00][I][main.cc:168] kvrocks unstable (commit 38e3c1ff)
[2026-10-14T08:29:29.661755+00:00][I][storage.cc:407] [storage] Success to load the data from disk: 39 ms
[2026-10-14T08:29:29.664412+00:00][I][worker.cc:77] [worker] Listening on: 127.0.0.1:6666
[2026-10-14T08:29:29.664664+00:00][I][worker.cc:77] [worker] Listening on: 127.0.0.1:6666
[2026-10-14T08:29:29.664820+00:00][I][worker.cc:77] [worker] Listening on: 127.0.0.1:6666
[2026-10-14T08:29:29.664952+00:00][I][worker.cc:77] [worker] Listening on: 127.0.0.1:6666
[2026-10-14T08:29:29.665076+00:00][I][worker.cc:77] [worker] Listening on: 127.0.0.1:6666
[2026-10-14T08:29:29.665196+00:00][I][worker.cc:77] [worker] Listening on: 127.0.0.1:6666
[2026-10-14T08:29:29.665315+00:00][I][worker.cc:77] [worker] Listening on: 127.0.0.1:6666
[2026-10-14T08:29:29.665459+00:00][I][worker.cc:77] [worker] Listening on: 127.0.0.1:6666
[2026-10-14T08:29:29.665560+00:00][W][server.cc:1957] [server] Increased maximum number of open files to 18464 (it's originally set to 1024)
[2026-10-14T08:29:29.665756+00:00][I][worker.cc:597] [worker] Thread #137250195089088 started
[2026-10-14T08:29:29.665792+00:00][I][worker.cc:597] [worker] Thread #137250203481792 started
[2026-10-14T08:29:29.665824+00:00][I][worker.cc:597] [worker] Thread #137250211874496 started
[2026-10-14T08:29:29.665882+00:00][I][worker.cc:597] [worker] Thread #137251058513600 started
[2026-10-14T08:29:29.665928+00:00][I][worker.cc:597] [worker] Thread #137251050120896 started
[2026-10-14T08:29:29.665976+00:00][I][worker.cc:597] [worker] Thread #137251041728192 started
[2026-10-14T08:29:29.666024+00:00][I][worker.cc:597] [worker] Thread #137251033335488 started
[2026-10-14T08:29:29.666067+00:00][I][worker.cc:597] [worker] Thread #137250237052608 started
[2026-10-14T08:29:29.666242+00:00][I][server.cc:245] [server] Ready to accept connections
[2026-10-14T08:29:31.669840+00:00][I][cmd_replication.cc:61] Slave 127.0.0.1:48994, listening port: 6667, announce ip: 127.0.0.1 asks for synchronization with next sequence: 1, replication id: not supported, and local sequence: 0
[2026-10-14T08:29:31.670092+00:00][I][cmd_replication.cc:113] New replica: 127.0.0.1:48994 was added, start incremental syncing
[2026-10-14T08:29:35.865230+00:00][I][event_listener.cc:133] [event_listener/flush_begin] column family: metadata, thread_id: 12, job_id: 3, reason: Write Buffer Full
[2026-10-14T08:29:35.982003+00:00][I][event_listener.cc:186] [event_listener/table_file_created] column family: metadata, file path: /tmp/m/db/000015.sst, file size: 55729925, job_id: 3, reason: flush, status: OK
[2026-10-14T08:29:35.982827+00:00][I][event_listener.cc:140] [event_listener/flush_completed] column family: metadata, thread_id: 12, job_id: 3, file: /tmp/m/db/000015.sst, reason: Write Buffer Full, is_write_slowdown: no, is_write_stall: no, largest seqno: 853, smallest seqno: 1
[2026-10-14T08:29:36.132625+00:00][I][event_listener.cc:133] [event_listener/flush_begin] column family: metadata, thread_id: 13, job_id: 4, reason: Write Buffer Full
[2026-10-14T08:29:36.261725+00:00][I][event_listener.cc:186] [event_listener/table_file_created] column family: metadata, file path: /tmp/m/db/000017.sst, file size: 55729952, job_id: 4, reason: flush, status: OK
[2026-10-14T08:29:36.262772+00:00][I][event_listener.cc:140] [event_listener/flush_completed] column family: metadata, thread_id: 13, job_id: 4, file: /tmp/m/db/000017.sst, reason: Write Buffer Full, is_write_slowdown: no, is_write_stall: no, largest seqno: 1708, smallest seqno: 854
```
