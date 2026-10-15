# tier3 selection criteria

Status: frozen
Date: 2026-03-30
Corpus scope: 60 released cases under `cases/`

## Goal

Freeze a **60-case core scored subset (`tier3`)** that extends `tier2` with the dense-system core-only promotion rows.

`tier3 = tier2 + 14 core-only promotion rows`

This is the package-wide core diagnosis denominator: it includes the structured rows plus the dense-system crash/parser/edge-case rows that are still valuable for component/locus/family scoring.

## Selection policy

A case is eligible for `tier3` if it satisfies all of the following:
1. historical bug/fix provenance in the released corpus;
2. acceptable replay/checker quality (`D1` or `D2`);
3. enough scorer-facing value for core diagnosis localization;
4. at minimum, stable `component_gold` + `code_locus_gold`/usable locus + `bug_family` + checker support.

Unlike `tier2`, this tier explicitly allows `G2` core-only rows when they are useful denominator-expansion rows inside dense systems.

## Composition rule

`tier3 = tier2 + core-only promotion rows`

- `tier2`: **46** rows
- core-only promotion: **14** rows
- Total: **60** rows

The core-only additions are:
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
- `rocksdb-10751-stalled-writes-shutdown`

## Peer-review summary

### Pass conditions met
- exactly **60** cases
- includes all **46** tier2 rows
- adds all **14** core-only dense-system rows
- preserves the distinction between structured scoring and broader core localization scoring
- all 60 released cases are covered; there is no release-only remainder
