# Symptom: Dragonfly #6761

When using the memcache protocol, sending STATS or VERSION commands inside a pipeline causes the process to crash. The commands return WOULD_BLOCK which is not properly handled in pipeline mode.
