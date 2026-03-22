# Verification: etcd #20893

```bash
#!/bin/bash
set -e

rm -rf /tmp/etcd-test
mkdir -p /tmp/etcd-test

# Start 3-member cluster with snapshot-count=2
bin/etcd --name m1 --data-dir /tmp/etcd-test/m1 \
  --listen-client-urls http://127.0.0.1:2379 --advertise-client-urls http://127.0.0.1:2379 \
  --listen-peer-urls http://127.0.0.1:2380 --initial-advertise-peer-urls http://127.0.0.1:2380 \
  --initial-cluster m1=http://127.0.0.1:2380,m2=http://127.0.0.1:2382,m3=http://127.0.0.1:2384 \
  --initial-cluster-token test --snapshot-count=2 &
bin/etcd --name m2 --data-dir /tmp/etcd-test/m2 \
  --listen-client-urls http://127.0.0.1:2381 --advertise-client-urls http://127.0.0.1:2381 \
  --listen-peer-urls http://127.0.0.1:2382 --initial-advertise-peer-urls http://127.0.0.1:2382 \
  --initial-cluster m1=http://127.0.0.1:2380,m2=http://127.0.0.1:2382,m3=http://127.0.0.1:2384 \
  --initial-cluster-token test --snapshot-count=2 &
bin/etcd --name m3 --data-dir /tmp/etcd-test/m3 \
  --listen-client-urls http://127.0.0.1:2383 --advertise-client-urls http://127.0.0.1:2383 \
  --listen-peer-urls http://127.0.0.1:2384 --initial-advertise-peer-urls http://127.0.0.1:2384 \
  --initial-cluster m1=http://127.0.0.1:2380,m2=http://127.0.0.1:2382,m3=http://127.0.0.1:2384 \
  --initial-cluster-token test --snapshot-count=2 &
sleep 3

# Add learner
bin/etcdctl --endpoints=http://127.0.0.1:2379 member add learner1 --peer-urls=http://127.0.0.1:2386 --learner

# Write keys to trigger snapshot
for i in $(seq 1 5); do
  bin/etcdctl --endpoints=http://127.0.0.1:2379 put key$i val$i
done
sleep 2

# Stop all
pkill -f "etcd.*etcd-test" || true
sleep 2

# Restart m1 with --force-new-cluster
bin/etcd --name m1 --data-dir /tmp/etcd-test/m1 \
  --listen-client-urls http://127.0.0.1:2379 --advertise-client-urls http://127.0.0.1:2379 \
  --listen-peer-urls http://127.0.0.1:2380 --initial-advertise-peer-urls http://127.0.0.1:2380 \
  --force-new-cluster &
sleep 3

# Check member list
MEMBERS=$(bin/etcdctl --endpoints=http://127.0.0.1:2379 member list 2>/dev/null)
MEMBER_COUNT=$(echo "$MEMBERS" | wc -l | tr -d ' ')
HAS_LEARNER=$(echo "$MEMBERS" | grep -c "learner" || true)

pkill -f "etcd.*etcd-test" 2>/dev/null || true
rm -rf /tmp/etcd-test

if [ "$MEMBER_COUNT" -eq 1 ] && [ "$HAS_LEARNER" -eq 0 ]; then
    echo "PASS: Bug is fixed — only one member, no learners"
else
    echo "FAIL: Bug is present — found $MEMBER_COUNT members, $HAS_LEARNER learners"
fi
```

- **FAIL:** The learner still appears in the member list after `--force-new-cluster`.
- **PASS:** Only one member (the recovered node itself) is in the member list.
