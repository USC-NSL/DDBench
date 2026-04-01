# FS28 selection criteria

Status: frozen
Date: 2026-03-30
Corpus scope: 62 released cases under `cases/`

## Goal

Freeze a **29-case headline-plus-expansion subset (`FS28`)** that preserves the original FS23 core while incorporating the six newly added Kafka/ZooKeeper rows as first-class benchmark members.

`FS28 = FS23 + 6 newly added Kafka/ZooKeeper rows`

This object is meant to be broader than the old FS23 headline cut while still staying disciplined on replay quality, hybrid diagnosis value, and structured gold completeness.

## Selection policy

A case is eligible for `FS28` only if all of the following hold.

1. **Historical bug/fix row**
   - real historical bug/fix provenance in the released corpus.

2. **Replay quality**
   - acceptable replay/checker quality (`D1` or `D2`).
   - no broken checker or missing replay path.

3. **Hybrid diagnosis value**
   - Preferred: `hybrid_necessity = yes`.
   - Allowed in `FS28`: `probable` rows **only when** they add clear system-family or failure-family value and still support strong structured gold.
   - In the current frozen `FS28`, 27 rows are `yes` and 2 rows are `probable` (`kafka-14334-delayed-fetch-purgatory`, `zookeeper-4846-fuzzy-snapshot-acl`).

4. **Gold completeness**
   - target is `G4-achievable` across the set.
   - every current `FS28` row is screened as `G4`.

5. **Diversity / value rule**
   - expansion is justified when it brings either:
     - a new system family with multiple strong rows, or
     - a materially new failure mode worth scoring separately.

## Why FS28 instead of FS23

The six new Kafka/ZooKeeper rows are too valuable to leave as mere appendix notes:
- they add **2 new system families**,
- they add more depth in coordinator, rebalance, ZAB ordering, snapshot/restart, and DIFF-sync propagation failures,
- and four of the six are strong `yes/G4` rows, while the remaining two still look valuable enough for inclusion under the broader FS28 bar.

So the right move is not to churn the old 23, but to **promote the object to FS28**.

## Frozen FS28 composition rule

- existing `FS23`: **23** rows
- Kafka additions: **3** rows
- ZooKeeper additions: **3** rows

Total = **29**

System-family composition:
- `etcd`: **4**
- `Kvrocks`: **4**
- `NATS`: **5**
- `raft`: **5**
- `Consul`: **2**
- `BookKeeper`: **1**
- `ClickHouse`: **1**
- `Dragonfly`: **1**
- `Kafka`: **3**
- `ZooKeeper`: **3**

## Frozen FS28 membership (exactly 29)

| corpus_case | system | bug family | hybrid | gold | inclusion rationale |
| --- | --- | --- | --- | --- | --- |
| `bookkeeper-2614-recovery-fencing-gap` | BookKeeper | `recovery-reconfiguration-failover` | `yes` | `G4` | Preserves the BookKeeper bridge anchor with a strong replicated-recovery truncation bug. |
| `clickhouse-98079-keeper-addwatch` | ClickHouse | `rpc-protocol-state-machine` | `yes` | `G4` | Preserves the ClickHouse protocol/state-machine bridge anchor. |
| `consul-8377-snapshot-restore-index` | Consul | `recovery-reconfiguration-failover` | `yes` | `G4` | Retains a strong Consul restore/divergence row. |
| `consul-9772-streaming-snapshot-cache` | Consul | `rpc-protocol-state-machine` | `yes` | `G4` | Retains a second Consul row with strong event-stream/state-machine value. |
| `dragonfly-6687-replica-rdb-encoding` | Dragonfly | `storage-io-path` | `yes` | `G4` | Retains a storage/replication bridge anchor. |
| `etcd-17158-delete-linearizability` | etcd | `replication-consistency` | `yes` | `G4` | Strong replication-consistency anchor. |
| `etcd-17529-watch-compaction-loss` | etcd | `replication-consistency` | `yes` | `G4` | Strong watcher/compaction hybrid row. |
| `etcd-20221-watch-restore-revision` | etcd | `replication-consistency` | `yes` | `G4` | Strong watch-restore hybrid row. |
| `etcd-20893-force-new-cluster-learner` | etcd | `recovery-reconfiguration-failover` | `yes` | `G4` | Strong recovery/reconfiguration membership row. |
| `kvrocks-2214-slave-sync-gap` | Kvrocks | `replication-consistency` | `yes` | `G4` | Strong replication-gap row with clear cross-node divergence. |
| `kvrocks-2520-namespace-fullsync` | Kvrocks | `recovery-reconfiguration-failover` | `yes` | `G4` | Strong recovery/full-sync row. |
| `kvrocks-3208-replication-watermark` | Kvrocks | `performance-resource-interaction` | `yes` | `G4` | Retains a measurable performance/resource replicated-system row. |
| `kvrocks-3356-replication-wal` | Kvrocks | `performance-resource-interaction` | `yes` | `G4` | Retains a second strong performance/resource replicated-system row. |
| `nats-6374-consumer-stuck-redelivery` | NATS | `recovery-reconfiguration-failover` | `yes` | `G4` | Strong failover-sensitive consumer-state row. |
| `nats-7308-delete-nonexistent-reset` | NATS | `rpc-protocol-state-machine` | `yes` | `G4` | Strong RPC/state-machine corruption row. |
| `nats-7718-subscription-leak` | NATS | `performance-resource-interaction` | `yes` | `G4` | Retains a resource-leak row with clear operational value. |
| `nats-7760-filter-stepdown` | NATS | `recovery-reconfiguration-failover` | `yes` | `G4` | Strong leader-stepdown stale-state row. |
| `nats-7817-workqueue-message-loss` | NATS | `replication-consistency` | `yes` | `G4` | Strong replication-consistency/message-loss row. |
| `raft-268-shutdown-deadlock` | raft | `recovery-reconfiguration-failover` | `yes` | `G4` | Strong shutdown/recovery race row. |
| `raft-358-negative-log-range` | raft | `recovery-reconfiguration-failover` | `yes` | `G4` | Strong snapshot-compaction failure row. |
| `raft-460-logcache-store-order` | raft | `replication-consistency` | `yes` | `G4` | Strong replication-consistency/log-cache row. |
| `raft-581-transfer-write-race` | raft | `recovery-reconfiguration-failover` | `yes` | `G4` | Strong failover/control-path transfer race row. |
| `raft-609-prevote-contact-liveness` | raft | `recovery-reconfiguration-failover` | `yes` | `G4` | Strong election-liveness/control-plane row. |
| `kafka-14334-delayed-fetch-purgatory` | Kafka | `performance-resource-interaction` | `probable` | `G4` | Included because it adds a real Kafka follower-fetch latency/performance path despite being slightly more repo-localized than the strongest rows. |
| `kafka-15170-endless-rebalance-loop` | Kafka | `recovery-reconfiguration-failover` | `yes` | `G4` | Included as a strong Kafka cooperative-rebalance/control-plane row. |
| `kafka-15784-txn-offset-atomicity` | Kafka | `replication-consistency` | `yes` | `G4` | Included as a strong Kafka coordinator atomicity/state-divergence row. |
| `zookeeper-4643-sync-epoch-ordering` | ZooKeeper | `recovery-reconfiguration-failover` | `yes` | `G4` | Included as a strong ZooKeeper ZAB ordering/data-loss row. |
| `zookeeper-4846-fuzzy-snapshot-acl` | ZooKeeper | `rpc-protocol-state-machine` | `probable` | `G4` | Included because the restart/fuzzy-snapshot ACL corruption path adds distinct ZooKeeper failure value even if it is a bit more borderline on strict hybrid necessity. |
| `zookeeper-4925-diff-sync-committedlog-hole` | ZooKeeper | `replication-consistency` | `yes` | `G4` | Included as a strong ZooKeeper DIFF-sync propagation/data-loss row. |


## Peer-review summary of the frozen FS28

### Pass conditions met
- exactly **29** cases
- **10** system families represented
- strong coverage of `recovery-reconfiguration-failover`, `replication-consistency`, `rpc-protocol-state-machine`, `performance-resource-interaction`, plus bridge `storage-io-path`
- all 29 screened as **G4-achievable**
- **27/29** screened as `hybrid=yes`
- **2/29** screened as `hybrid=probable`, both retained deliberately for system/failure-family expansion value

### Borderline-but-included rows
- `kafka-14334-delayed-fetch-purgatory`
- `zookeeper-4846-fuzzy-snapshot-acl`

These two stay in FS28 because the object is intentionally broader than the old FS23 and their added benchmark value outweighs their slightly weaker hybrid purity.
