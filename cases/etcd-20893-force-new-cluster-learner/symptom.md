# Symptom

When using `--force-new-cluster` to recover from a snapshot on a node that previously had a learner member, the learner is not removed from the member list. The forced single-node cluster still shows the learner as a member, even though the learner node is not running and cannot be reached.

This makes the recovered cluster inconsistent: the member list includes a learner that should have been cleaned up during the force-new-cluster recovery process.
