# DDBench Tier Definitions

Status: frozen 2026-03-30
Corpus: 61 verified bug cases (60 active + 1 removed: `clickhouse-98079-keeper-addwatch`)

## 1. Motivation

DDBench stratifies its corpus into three nested difficulty tiers
(`tier1 ⊂ tier2 ⊂ tier3`) so that evaluation can separate
*distributed-systems diagnostic skill* from *local bug-localization skill*.
The tiers are not defined by surface-level bug complexity but by the
**diagnostic reasoning surface** a solver must traverse to produce a
correct root-cause explanation and a replayable fix-validation plan.

Each case is scored on two orthogonal axes, and tier membership is a
monotone function of the two.

## 2. Two orthogonal admission axes

### 2.1 Hybrid necessity (`H`)

Measures whether root-cause diagnosis requires *combining* runtime
evidence (cluster traces, logs, crash reports, test failures) with
*repository-level code reasoning* (identifying the culprit code path).

| Value | Definition |
|-------|------------|
| `yes` (H₂)    | Neither runtime evidence nor code inspection is independently sufficient. The culprit is only recoverable by jointly reasoning over the two. |
| `probable` (H₁) | Diagnosis is hybrid in spirit, but an existing regression test, crash dump, or sanitizer output substantially shortcuts one side of the reasoning. |
| `no` (H₀)     | Runtime evidence alone (stack trace, race-detector report, parser crash) effectively localizes the bug; code reasoning is confirmatory, not required. |

### 2.2 Gold completeness (`G`)

Measures the recoverability of the five-field structured diagnosis gold
used for scoring: **component**, **code locus**, **bug family**,
**causal chain**, **validation plan**.

| Value | Definition |
|-------|------------|
| `G4` | All five fields are cleanly derivable from audited materials. |
| `G3` | Four of five fields are clean; typically code locus is imprecise. |
| `G2` | Only component and (approximate) code locus are stable; causal chain and validation gold are not robustly frozen. |

## 3. Tier definitions

Let `C` denote the 61-case corpus. Tiers are defined as nested subsets
admitted by successively weaker `(H, G)` thresholds.

### 3.1 Tier 1 — *hybrid-required headline package* (|T₁| = 31)

```
T₁ = { c ∈ C : H(c) = yes  ∧  G(c) = G4 }
     ∪ { c ∈ C : H(c) = probable ∧ G(c) = G4 ∧ c adds a new system family or failure mode }
```

Properties:

- Every case requires genuine hybrid runtime-plus-code reasoning
  (29/31 `H=yes`, 2/31 `H=probable` retained for system-family
  diversity: `kafka-14334-delayed-fetch-purgatory`,
  `zookeeper-4846-fuzzy-snapshot-acl`).
- Every case supports the full five-field structured gold.
- Covers 11 system families and 6 bug families, with emphasis on
  replication-consistency, recovery/reconfiguration/failover,
  RPC/protocol state-machine, cross-node concurrency races, and
  performance/resource interactions.
- **Interpretation:** failures on T₁ reflect a shortfall in
  *distributed-systems reasoning*, not in bug-localization mechanics.

### 3.2 Tier 2 — *full structured-diagnosis package* (|T₂| = 46)

```
T₂ = T₁ ∪ { c ∈ C \ T₁ :
             scorer-facing value for structured diagnosis
             ∧ G(c) ≥ G3
             ∧ (H(c) ∈ {yes, probable} ∨ runtime-evidence is hybrid-adjacent) }
```

Properties:

- Admits `probable` and selected `no` cases that still support the
  full structured scoring package (`G4`, with a small number of `G3`
  admitted where component/family/causal-chain/validation remain
  scorable but code locus is soft).
- Adds 15 cases including `raft-358-negative-log-range` (demoted from
  T₁ because its symptom — a negative compaction range in the logs —
  nearly hands the fix guard to the solver), and 14 structured
  promotions (e.g. `etcd-19172-embed-data-race`, where the Go race
  detector localizes the bug but code context still refines it).
- **Interpretation:** the structured scoring denominator. Failures on
  T₂ \ T₁ reflect weakness in producing full five-field diagnoses when
  runtime evidence is unusually generous.

### 3.3 Tier 3 — *core localization package* (|T₃| = 61)

```
T₃ = T₂ ∪ { c ∈ C \ T₂ :
             stable component ∧ usable code locus
             ∧ bug family defined
             ∧ replay/checker supported }
```

Properties:

- Admits `G2` core-only cases, primarily dense-system crash/parser/
  edge-case rows (e.g. Dragonfly command-parser crashes, float NaN
  handling, RocksDB shutdown stall).
- All 61 corpus cases are T₃-eligible under the stated replay/checker
  quality floor (D1 or D2).
- **Interpretation:** the broadest localization denominator. T₃ \ T₂
  isolates *runtime-sufficient* bugs — they occur inside distributed
  services but the diagnostic challenge is largely local.

## 4. Monotonicity and difficulty gradient

The admission rule yields the nested relation

```
T₁ ⊂ T₂ ⊂ T₃
```

with the following monotone relaxations from T₁ to T₃:

| Axis | T₁ threshold | T₂ threshold | T₃ threshold |
|------|-------------|-------------|-------------|
| Hybrid necessity `H` | `yes` (2 `probable` exceptions) | `yes` / `probable` (+ hybrid-adjacent `no`) | any |
| Gold completeness `G` | `G4` | `G3`–`G4` | `G2`–`G4` |
| Reasoning surface | distributed runtime **and** code | distributed runtime **or** code (evidence-assisted) | often single-node local |

Because both axes relax monotonically, diagnostic difficulty — defined
as the reasoning surface required for a correct root-cause explanation —
decreases monotonically from T₁ to T₃.

## 5. Replay-quality floor (all tiers)

All three tiers inherit a replay/checker-quality precondition:

- historical bug/fix provenance in the released corpus,
- a working automated reproduction (`D1` or `D2`),
- a stable pass/fail checker.

No case is admitted to any tier without these properties; tiering
governs *diagnostic difficulty*, not *reproducibility*.

## 6. Canonical examples

| Tier boundary | Case | Why it sits here |
|---------------|------|------------------|
| T₁ core | `etcd-17158-delete-linearizability` | Linearizability anomaly + unsafe batch-tx deletion path; neither visible alone. |
| T₁ `probable` exception | `kafka-14334-delayed-fetch-purgatory` | Hybrid in spirit but regression test shortcuts code reasoning; admitted for Kafka family coverage. |
| T₂ promotion (T₁ demotion) | `raft-358-negative-log-range` | Symptom (negative range in logs) effectively reveals the missing guard check; fails strict hybrid bar. |
| T₂ \ T₁ | `etcd-19172-embed-data-race` | Go race-detector output nearly localizes; code reasoning confirmatory. |
| T₃ \ T₂ | `dragonfly-6764-hincrbyfloat-nan` | NaN parser crash; stack trace + single function suffice. `G2` core-only. |

## 7. Intended evaluation use

- **T₁** — report primary distributed-systems diagnostic accuracy.
  Headline number for claims about distributed-reasoning ability.
- **T₂** — report structured five-field diagnosis scores
  (component / locus / family / causal chain / validation).
  Used for fine-grained scoring comparisons across systems.
- **T₃** — report core localization recall. Captures whether a solver
  can at least identify component and locus on any corpus case,
  including runtime-sufficient crashes.

Reporting the triple `(acc@T₁, struct@T₂, loc@T₃)` yields a compact
profile that separates distributed-reasoning skill from generic
bug-localization skill.
