# Test Output

Obtained by starting a master-replica pair, running `redis-benchmark -p 13356 -t set -n 1000000 -r 1000000 -d 256 -c 50 -P 32` against the master, then measuring the master data directory size before and after the benchmark.

## Output

```
Starting master on port 13356...
Starting replica on port 13357...
Checking replication status...
connected_slaves:1
slave0:ip=127.0.0.1,port=13357,offset=0,lag=0
Initial master dir size: 4424KB

Running redis-benchmark (1M SET operations, 256-byte values, 50 clients, pipeline 32)...
SET: 87481.41 requests per second, p50=8.159 msec

Waiting 10 seconds for WAL accumulation...
Final master dir size: 546020KB
WAL growth: 541596KB

FAIL: Bug is present — WAL grew by 541596KB (> 512MB, unbounded growth)
```
