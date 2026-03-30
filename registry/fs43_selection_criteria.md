# FS43 selection criteria

Status: frozen
Date: 2026-03-30
Corpus scope: 62 released cases under `cases/`

## Goal

Freeze a **43-case structured scored subset (`FS43`)** that extends the frozen `FS29` with all rows that should support full structured diagnosis scoring.

`FS43 = FS29 + 14 structured-promotion rows`

This is the new middle tier:
- broader than the headline package,
- still intended to support structured diagnosis fields,
- but no longer limited to the strictest hybrid-required semantics.

## Selection policy

A case is eligible for `FS43` if it satisfies all of the following:
1. historical bug/fix provenance in the released corpus;
2. acceptable replay/checker quality (`D1` or `D2`);
3. scorer-facing value for structured diagnosis, meaning the row is useful for component/locus/family/causal-chain/validation scoring;
4. target `G4` structured gold, with a small number of still-imperfect rows allowed only when they are part of the inherited promotion track and remain important for the structured package.

## Composition rule

`FS43 = FS29 + S14 structured-promotion rows`

- `FS29`: **29** rows
- `S14 structured-promotion`: **14** rows
- Total: **43** rows

The `S14` additions are:
- `etcd-20704-leasing-linearizability`
- `etcd-19172-embed-data-race`
- `dragonfly-6738-pipeline-block`
- `kvrocks-2512-slaveof-deadlock`
- `kvrocks-3148-namespace-delete`
- `kvrocks-3339-xreadgroup-double`
- `nats-6455-reserved-resource-leak`
- `nats-7707-wq-consumer-map-crash`
- `nats-7726-mixed-filter`
- `nats-7852-filter-perf`
- `raft-517-candidate-appendentries-race`
- `raft-rs-345-readindex-config-change`
- `consul-12295-acl-replication-stall`
- `raft-rs-221-campaign-conf-change`

## Tier semantics

- `FS29`: headline-plus-expansion package
- `FS43`: full structured diagnosis package
- `FS56`: full core scored package

## Peer-review summary

### Pass conditions met
- exactly **43** cases
- includes all **29** FS29 rows
- adds all **14** historical structured-promotion rows
- all rows remain scored-package worthy
- overwhelming majority are `G4`; two inherited component-locus-soft rows remain visible as structured inclusions rather than headline rows
- this tier is the right place for `probable` hybrid rows and non-headline structured rows
