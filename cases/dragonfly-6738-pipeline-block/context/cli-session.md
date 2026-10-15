# CLI Session

Obtained by starting `./build-dbg/dragonfly --port 6379 --logtostderr --proactor_threads 2 --dbfilename=""` from the buggy build and running a small Python socket client against it. The client acts like a queue worker: it writes `BRPOPLPUSH bull:jobs:wait bull:jobs:active 3` twice to one connection in a single write and prints when each reply arrives. One second later, a second connection enqueues a job with `EVAL "return redis.call('RPUSH', KEYS[1], ARGV[1])" 1 bull:jobs:wait job-1`. The client then repeats the scenario with one `BRPOPLPUSH` sent by itself on a fresh connection (job `job-2`). Times are seconds since each worker connection sent its commands.

## Output

```
[ 0.004s] worker: wrote 2 x BRPOPLPUSH bull:jobs:wait bull:jobs:active 3 in one write
[ 1.007s] producer: EVAL RPUSH bull:jobs:wait job-1 -> :1
[ 4.009s] worker: reply 1: 'job-1'
[ 4.009s] worker: reply 2: None
[ 0.001s] worker (one command at a time): wrote BRPOPLPUSH bull:jobs:wait bull:jobs:active 3
[ 1.002s] producer: EVAL RPUSH bull:jobs:wait job-2 -> :1
[ 1.002s] worker (one command at a time): reply: 'job-2'
```
