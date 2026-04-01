# FS55 selection criteria

Status: frozen
Date: 2026-03-30
Corpus scope: 62 released cases under `cases/`

## Goal

Freeze a **56-case core scored subset (`FS55`)** that extends `FS42` with the dense-system core-only promotion rows.

`FS55 = FS42 + 13 core-only promotion rows`

This is the package-wide core diagnosis denominator: it includes the structured rows plus the dense-system crash/parser/edge-case rows that are still valuable for component/locus/family scoring.

## Selection policy

A case is eligible for `FS55` if it satisfies all of the following:
1. historical bug/fix provenance in the released corpus;
2. acceptable replay/checker quality (`D1` or `D2`);
3. enough scorer-facing value for core diagnosis localization;
4. at minimum, stable `component_gold` + `code_locus_gold`/usable locus + `bug_family` + checker support.

Unlike `FS42`, this tier explicitly allows `G2` core-only rows when they are useful denominator-expansion rows inside dense systems.

## Composition rule

`FS55 = FS42 + C13 core-only promotion rows`

- `FS42`: **43** rows
- `C13 core-only promotion`: **13** rows
- Total: **56** rows

The `C13` additions are:
- `dragonfly-6614-monitor-multiexec`
- `dragonfly-6619-evalsha-empty`
- `dragonfly-6654-mc-reply-large`
- `dragonfly-6753-populate-sigfpe`
- `dragonfly-6761-mc-pipeline-crash`
- `dragonfly-6764-hincrbyfloat-nan`
- `dragonfly-6819-stale-expiry`
- `dragonfly-6825-config-overflow`
- `dragonfly-6856-flushslots-oob`
- `dragonfly-6907-ftsearch-vector-crash`
- `dragonfly-6909-search-nonfinite`
- `dragonfly-6912-rdb-encoding`
- `kvrocks-3315-zdiff-crash`

## Release-only remainder outside FS55

The remaining released rows are still public/executable, but stay outside the current scored denominator:
- `bookkeeper-4701-fencing-race`
- `etcd-19179-watch-tombstone-compact`
- `rabbitmq-12635-qq-snapshot-crash`
- `ra-439-election-livelock`
- `rocksdb-10751-stalled-writes-shutdown`
- `seastar-2202-cross-shard-realloc`

## Peer-review summary

### Pass conditions met
- exactly **56** cases
- includes all **43** FS42 rows
- adds all **13** core-only dense-system rows
- preserves the distinction between structured scoring and broader core localization scoring
- leaves **6** released rows outside the scored denominator
