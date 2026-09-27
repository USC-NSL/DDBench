# Test Output

Obtained by starting a 3-member etcd cluster, adding a learner via `etcdctl member add learner1 --peer-urls=http://127.0.0.1:12386 --learner`, writing keys to trigger a snapshot, stopping all members, restarting m1 with `--force-new-cluster`, then running `etcdctl member list` against the recovered cluster.

## Output

```
Member 853842e1217b7b1a added as learner to cluster 1ea17005bfd3ceaf

ETCD_NAME="learner1"
ETCD_INITIAL_CLUSTER="m1=http://127.0.0.1:12380,m3=http://127.0.0.1:12384,learner1=http://127.0.0.1:12386,m2=http://127.0.0.1:12382"
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://127.0.0.1:12386"
ETCD_INITIAL_CLUSTER_STATE="existing"

$ etcdctl --endpoints=http://127.0.0.1:12379 member list
3bf6e745fd679980, started, m1, http://127.0.0.1:12380, http://127.0.0.1:12379, false
853842e1217b7b1a, unstarted, , http://127.0.0.1:12386, , true
```
