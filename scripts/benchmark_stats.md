# Benchmark Shape and Basic Metrics

Source: `registry/case_registry.json` (version 2.0.0, generated 2026-10-15T03:06:10Z).

## Totals

| Metric | Value |
|---|---|
| cases | 60 |
| projects | 13 |
| languages | 5 |
| system families | 6 |
| bug families raw | 13 |
| bug categories | 5 |
| oracle types | 6 |
| cases with solution | 60 |
| cases with gold complete | 60 |
| cases with context dir | 57 |
| cases with oracle harness files | 13 |
| cases with submodules | 22 |

## Distribution: Projects

| Bucket | Count | Share |
|---|---:|---:|
| dragonfly | 14 | 23.3% |
| nats | 9 | 15.0% |
| kvrocks | 8 | 13.3% |
| etcd | 7 | 11.7% |
| raft | 6 | 10.0% |
| consul | 3 | 5.0% |
| kafka | 3 | 5.0% |
| zookeeper | 3 | 5.0% |
| bookkeeper | 2 | 3.3% |
| raft-rs | 2 | 3.3% |
| ra | 1 | 1.7% |
| rabbitmq | 1 | 1.7% |
| rocksdb | 1 | 1.7% |

## Distribution: Languages

| Bucket | Count | Share |
|---|---:|---:|
| Go | 25 | 41.7% |
| C++ | 23 | 38.3% |
| Java | 8 | 13.3% |
| Erlang | 2 | 3.3% |
| Rust | 2 | 3.3% |

## Distribution: System families

| Bucket | Count | Share |
|---|---:|---:|
| kv-store | 22 | 36.7% |
| consensus | 21 | 35.0% |
| messaging | 10 | 16.7% |
| service-mesh | 3 | 5.0% |
| streaming | 3 | 5.0% |
| storage-engine | 1 | 1.7% |

## Distribution: Oracle types

| Bucket | Count | Share |
|---|---:|---:|
| CRASH | 24 | 40.0% |
| OUTPUT | 22 | 36.7% |
| METRIC | 5 | 8.3% |
| LOG | 5 | 8.3% |
| HANG | 3 | 5.0% |
| RACE | 1 | 1.7% |

## Distribution: Surface tier (registry field)

| Bucket | Count | Share |
|---|---:|---:|
| tier1 | 31 | 51.7% |
| tier2 | 15 | 25.0% |
| tier3 | 14 | 23.3% |

## Distribution: Surface tier (membership files)

| Bucket | Count | Share |
|---|---:|---:|
| tier3 | 60 | 100.0% |

## Distribution: Contamination tier

| Bucket | Count | Share |
|---|---:|---:|
| E-low | 23 | 38.3% |
| E-med | 21 | 35.0% |
| E-high | 16 | 26.7% |

## Distribution: Source URL kind

| Bucket | Count | Share |
|---|---:|---:|
| github-issue | 49 | 81.7% |
| jira | 6 | 10.0% |
| github-pr | 5 | 8.3% |

## Distribution: Bug categories (5-way)

| Category | Count | Share | Description |
|---|---:|---:|---|
| Input-triggered crashes | 10 | 16.7% | Server-side crashes, assertions, or arithmetic faults (SIGFPE, OOB) triggered by malformed or edge-case client inputs such as empty/zero fields, non-finite floats, or oversized values. Probes single-node robustness to adversarial and corner-case requests. |
| Concurrency hazards | 11 | 18.3% | Data races, deadlocks, and livelocks arising from interleavings between client requests, background workers, and state transitions. Reproduction requires specific thread/goroutine scheduling. |
| Replication & consistency violations | 11 | 18.3% | Cross-replica divergence, lost updates, linearizability gaps, and silent data corruption on the leader-follower or log-replication path. Detectable only by cross-replica or invariant oracles. |
| Protocol & recovery failures | 19 | 31.7% | Defects in cluster-coordination protocols and recovery paths — leader election, membership and configuration change, snapshot/WAL replay, and RPC state-machine transitions — that surface after crashes, failovers, or other protocol edge cases. |
| Resource & delivery anomalies | 9 | 15.0% | Resource leaks, performance degradation, storage I/O-path misbehavior, and delivery/notification failures that degrade service availability or SLOs without crashing the server. |

## Distribution: Raw bug_family labels (fine-grained)

| Raw label | Count | Share | Rolled up into |
|---|---:|---:|---|
| recovery-reconfiguration-failover | 11 | 18.3% | Protocol & recovery failures |
| replication-consistency | 10 | 16.7% | Replication & consistency violations |
| rpc-protocol-state-machine | 8 | 13.3% | Protocol & recovery failures |
| crash-on-invalid-input | 7 | 11.7% | Input-triggered crashes |
| race-condition | 4 | 6.7% | Concurrency hazards |
| deadlock-livelock | 4 | 6.7% | Concurrency hazards |
| input-validation-overflow | 3 | 5.0% | Input-triggered crashes |
| concurrency-crash | 3 | 5.0% | Concurrency hazards |
| performance-resource-interaction | 3 | 5.0% | Resource & delivery anomalies |
| storage-io-path | 2 | 3.3% | Resource & delivery anomalies |
| notification-delivery-failure | 2 | 3.3% | Resource & delivery anomalies |
| resource-leak | 2 | 3.3% | Resource & delivery anomalies |
| silent-data-corruption | 1 | 1.7% | Replication & consistency violations |

## Size metrics (per case)

| Artifact | n | min | p25 | median | mean | p75 | max | total |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| symptom_md_lines | 60 | 5 | 8.0 | 10.0 | 10.9 | 12.0 | 22 | 654 |
| reproduce_md_lines | 60 | 22 | 36.0 | 58.0 | 61.98 | 78.75 | 141 | 3719 |
| readme_md_lines | 60 | 20 | 39.0 | 39.0 | 40.53 | 43.0 | 46 | 2432 |
| reproduce_sh_lines | 60 | 62 | 96.0 | 130.5 | 149 | 176.0 | 430 | 8940 |
| gold_patch_lines | 60 | 12 | 18.25 | 37.0 | 86.1 | 62.25 | 909 | 5166 |
| solution_md_lines | 60 | 22 | 24.25 | 40.5 | 41.85 | 54.5 | 85 | 2511 |
| context_files_per_case | 60 | 0 | 1.0 | 1.0 | 1.28 | 2.0 | 3 | 77 |
| oracle_harness_files_per_case | 60 | 0 | 0.0 | 0.0 | 0.33 | 0.0 | 5 | 20 |

## Cross-tab: surface tier × language

| | C++ | Erlang | Go | Java | Rust | total |
|---|---:|---:|---:|---:|---:|---:|
| tier1 | 5 | 2 | 16 | 8 | 0 | 31 |
| tier2 | 4 | 0 | 9 | 0 | 2 | 15 |
| tier3 | 14 | 0 | 0 | 0 | 0 | 14 |
| **total** | 23 | 2 | 25 | 8 | 2 | 60 |

## Cross-tab: oracle type × language

| | C++ | Erlang | Go | Java | Rust | total |
|---|---:|---:|---:|---:|---:|---:|
| CRASH | 10 | 0 | 13 | 1 | 0 | 24 |
| HANG | 1 | 0 | 0 | 2 | 0 | 3 |
| OUTPUT | 8 | 1 | 7 | 5 | 1 | 22 |
| METRIC | 2 | 0 | 3 | 0 | 0 | 5 |
| RACE | 1 | 0 | 0 | 0 | 0 | 1 |
| LOG | 1 | 1 | 2 | 0 | 1 | 5 |
| **total** | 23 | 2 | 25 | 8 | 2 | 60 |

## Cross-tab: bug category × system family

| | consensus | kv-store | messaging | service-mesh | storage-engine | streaming | total |
|---|---:|---:|---:|---:|---:|---:|---:|
| Input-triggered crashes | 0 | 10 | 0 | 0 | 0 | 0 | 10 |
| Concurrency hazards | 6 | 3 | 1 | 0 | 1 | 0 | 11 |
| Replication & consistency violations | 7 | 2 | 1 | 0 | 0 | 1 | 11 |
| Protocol & recovery failures | 8 | 2 | 5 | 3 | 0 | 1 | 19 |
| Resource & delivery anomalies | 0 | 5 | 3 | 0 | 0 | 1 | 9 |
| **total** | 21 | 22 | 10 | 3 | 1 | 3 | 60 |
