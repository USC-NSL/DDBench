"""Shared bug-family taxonomy for the ddbench benchmark.

The registry (``registry/case_registry.json``) labels each case with one of
13 fine-grained ``bug_family`` values. For paper-facing reports we collapse
those into 5 coarse categories, each with a plain-English description.

Both ``benchmark_stats.py`` (here) and ``scan_pass_rates.py`` (in the parent
ddbench repo) import from this module so the taxonomy stays consistent.

Exports
-------
BUG_CATEGORIES       : ordered list of (name, description, [raw_labels]) tuples
CATEGORY_ORDER       : list[str]          -- canonical ordering for tables
FAMILY_TO_CATEGORY   : dict[str, str]     -- raw bug_family -> coarse name
CATEGORY_DESCRIPTIONS: dict[str, str]     -- coarse name -> description
"""

from __future__ import annotations


BUG_CATEGORIES: list[tuple[str, str, list[str]]] = [
    (
        "Input-triggered crashes",
        "Server-side crashes, assertions, or arithmetic faults (SIGFPE, OOB) "
        "triggered by malformed or edge-case client inputs such as empty/zero "
        "fields, non-finite floats, or oversized values. Probes single-node "
        "robustness to adversarial and corner-case requests.",
        ["crash-on-invalid-input", "input-validation-overflow"],
    ),
    (
        "Concurrency hazards",
        "Data races, deadlocks, and livelocks arising from interleavings "
        "between client requests, background workers, and state transitions. "
        "Reproduction requires specific thread/goroutine scheduling.",
        ["race-condition", "deadlock-livelock", "concurrency-crash"],
    ),
    (
        "Replication & consistency violations",
        "Cross-replica divergence, lost updates, linearizability gaps, and "
        "silent data corruption on the leader-follower or log-replication "
        "path. Detectable only by cross-replica or invariant oracles.",
        ["replication-consistency", "silent-data-corruption"],
    ),
    (
        "Protocol & recovery failures",
        "Defects in cluster-coordination protocols and recovery paths — "
        "leader election, membership and configuration change, snapshot/WAL "
        "replay, and RPC state-machine transitions — that surface after "
        "crashes, failovers, or other protocol edge cases.",
        ["recovery-reconfiguration-failover", "rpc-protocol-state-machine"],
    ),
    (
        "Resource & delivery anomalies",
        "Resource leaks, performance degradation, storage I/O-path "
        "misbehavior, and delivery/notification failures that degrade "
        "service availability or SLOs without crashing the server.",
        [
            "performance-resource-interaction",
            "resource-leak",
            "notification-delivery-failure",
            "storage-io-path",
        ],
    ),
]

CATEGORY_ORDER: list[str] = [name for name, _desc, _fams in BUG_CATEGORIES]

FAMILY_TO_CATEGORY: dict[str, str] = {
    fam: name for name, _desc, fams in BUG_CATEGORIES for fam in fams
}

CATEGORY_DESCRIPTIONS: dict[str, str] = {
    name: desc for name, desc, _fams in BUG_CATEGORIES
}


def categorize(bug_family: str) -> str:
    """Return the coarse category for a raw bug_family label.

    Unknown labels map to ``"uncategorized"`` — callers should treat that as
    a data-quality signal to surface (the registry has likely grown a new
    raw label that needs to be rolled into ``BUG_CATEGORIES``).
    """
    return FAMILY_TO_CATEGORY.get(bug_family, "uncategorized")
