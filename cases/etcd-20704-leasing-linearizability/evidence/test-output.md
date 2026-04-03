# Test Output

Obtained by running a linearizability test that performs concurrent `Delete` + `Put` operations through the leasing cache, then compares the cache result with a direct etcd `Get`, against a single-node etcd cluster.

## Output

```
Starting single-node etcd...
Running leasing linearizability test...
BUG at iteration 7: leasing cache says 1 kvs, etcd says 0 kvs
BUG_DETECTED
exit status 1
```
