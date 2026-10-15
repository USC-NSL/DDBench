# Reproduce: etcd #20893

## Step 1: Start a 3-member etcd cluster with low snapshot count

```bash
rm -rf /tmp/etcd-test
mkdir -p /tmp/etcd-test

# Member 1
bin/etcd --name m1 \
  --data-dir /tmp/etcd-test/m1 \
  --listen-client-urls http://127.0.0.1:2379 \
  --advertise-client-urls http://127.0.0.1:2379 \
  --listen-peer-urls http://127.0.0.1:2380 \
  --initial-advertise-peer-urls http://127.0.0.1:2380 \
  --initial-cluster m1=http://127.0.0.1:2380,m2=http://127.0.0.1:2382,m3=http://127.0.0.1:2384 \
  --initial-cluster-token test \
  --snapshot-count=2 &

# Member 2
bin/etcd --name m2 \
  --data-dir /tmp/etcd-test/m2 \
  --listen-client-urls http://127.0.0.1:2381 \
  --advertise-client-urls http://127.0.0.1:2381 \
  --listen-peer-urls http://127.0.0.1:2382 \
  --initial-advertise-peer-urls http://127.0.0.1:2382 \
  --initial-cluster m1=http://127.0.0.1:2380,m2=http://127.0.0.1:2382,m3=http://127.0.0.1:2384 \
  --initial-cluster-token test \
  --snapshot-count=2 &

# Member 3
bin/etcd --name m3 \
  --data-dir /tmp/etcd-test/m3 \
  --listen-client-urls http://127.0.0.1:2383 \
  --advertise-client-urls http://127.0.0.1:2383 \
  --listen-peer-urls http://127.0.0.1:2384 \
  --initial-advertise-peer-urls http://127.0.0.1:2384 \
  --initial-cluster m1=http://127.0.0.1:2380,m2=http://127.0.0.1:2382,m3=http://127.0.0.1:2384 \
  --initial-cluster-token test \
  --snapshot-count=2 &

sleep 3
```

## Step 2: Add a learner member

```bash
bin/etcdctl --endpoints=http://127.0.0.1:2379 member add learner1 \
  --peer-urls=http://127.0.0.1:2386 \
  --learner
```

## Step 3: Write enough keys to trigger a snapshot

```bash
for i in $(seq 1 5); do
  bin/etcdctl --endpoints=http://127.0.0.1:2379 put key$i val$i
done
sleep 2
```

## Step 4: Stop all members

```bash
pkill -f "etcd.*etcd-test" || true
sleep 2
```

## Step 5: Restart member 1 with --force-new-cluster

```bash
bin/etcd --name m1 \
  --data-dir /tmp/etcd-test/m1 \
  --listen-client-urls http://127.0.0.1:2379 \
  --advertise-client-urls http://127.0.0.1:2379 \
  --listen-peer-urls http://127.0.0.1:2380 \
  --initial-advertise-peer-urls http://127.0.0.1:2380 \
  --force-new-cluster &
sleep 3
```

## Step 6: Check the member list

```bash
bin/etcdctl --endpoints=http://127.0.0.1:2379 member list -w table
```

## Expected result (bug present)
The learner member still appears in the member list even though `--force-new-cluster` should have removed all non-self members.

## Oracle verdict

`./bench.sh reproduce etcd-20893-force-new-cluster-learner` rebuilds the worktree and runs the oracle (`reproduce.sh`):

- **FAIL** (exit 1): after a learner is added to a 3-member cluster (`--snapshot-count=2`), 10 keys are written, all members are stopped and `m1` is restarted with `--force-new-cluster`, `member list` on `m1` shows more than one member (e.g. the learner) or does not show `m1`. A worktree that does not build, a cluster that does not become healthy within 60 s, a failed `put`, or a restarted `m1` that does not come up within 30 s or cannot answer `member list`, is also FAIL.
- **PASS** (exit 0): `member list` on the restarted member lists exactly one member, `m1`.
- **ERROR** (exit 2): the learner cannot be added or does not appear in the member list, or the case is not set up (`REBUILD.sh`, the `etcd` or the `etcdctl` binary is missing).
