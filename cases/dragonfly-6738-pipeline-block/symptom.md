# Symptom

Queue workers that wait for jobs with blocking list pops pick up jobs late. After a producer pushes a job, a worker blocked in `BRPOPLPUSH` does not get it right away; it gets it seconds later, typically after a multiple of its blocking timeout. The same workload on Redis delivers jobs within milliseconds.

## Observable behavior

- First seen with a Bull-based job queue (n8n in queue mode). Producers enqueue jobs with a Lua script (`EVALSHA` doing `RPUSH`, `ZADD`, `PUBLISH`), and workers dequeue with `BRPOPLPUSH <wait-list> <active-list> 5`. A job takes 15-50 s to be picked up instead of about 1.5 s. It happens with one or several workers and with 1 or 2 proactor threads.
- `MONITOR` shows the push executing and the list growing, while the worker connections keep issuing `BRPOPLPUSH ... 5` roughly every 5 seconds before the job finally reaches a worker.
- The worker client pipelines: it writes several commands, including several blocking pops, to one connection without waiting for each reply.
- The delay does not depend on Lua. When a connection has several `BRPOPLPUSH` (or `BLPOP`) commands pipelined and another client pushes an element with plain `RPUSH`/`LPUSH`, the client receives the popped element only after the other pops pipelined on that connection have timed out.
- Replies to ordinary commands are delayed too. If a client pipelines `SET`, `PING` and then a `BLPOP` on an empty list, it receives the `SET` and `PING` replies only when the `BLPOP` times out.
- The same commands sent one at a time, each waiting for its reply, behave normally. No errors are logged, and the server keeps serving other connections.
