# MONITOR Log

Obtained by running `redis-cli -p 6379 MONITOR` against the buggy build (`./build-dbg/dragonfly --port 6379 --logtostderr --proactor_threads 2 --dbfilename=""`) during the session in `cli-session.md`: a worker connection writes two `BRPOPLPUSH bull:jobs:wait bull:jobs:active 3` in one write, a producer enqueues `job-1` with `EVAL ... RPUSH` one second later, and then a worker sends a single `BRPOPLPUSH` on a new connection and a producer enqueues `job-2`.

## Output

```
OK
1791998409.9193486 [0 127.0.0.1:49430] "BRPOPLPUSH" "bull:jobs:wait" "bull:jobs:active" "3"
1791998410.9198076 [0 127.0.0.1:35318] "EVAL" "return redis.call('RPUSH', KEYS[1], ARGV[1])" "1" "bull:jobs:wait" "job-1"
1791998410.9216986 [0 lua] "RPUSH" "bull:jobs:wait" "job-1"
1791998410.9222816 [0 127.0.0.1:49430] "BRPOPLPUSH" "bull:jobs:wait" "bull:jobs:active" "3"
1791998413.9254866 [0 127.0.0.1:35330] "BRPOPLPUSH" "bull:jobs:wait" "bull:jobs:active" "3"
1791998414.9251116 [0 127.0.0.1:35342] "EVAL" "return redis.call('RPUSH', KEYS[1], ARGV[1])" "1" "bull:jobs:wait" "job-2"
1791998414.9252846 [0 lua] "RPUSH" "bull:jobs:wait" "job-2"
```
