# Symptom

Rapid cycles of `JSON.SET` and `DEL` on keys containing nested JSON structures create orphaned JSON objects that are not properly cleaned up. This corrupts internal memory tracking counters and eventually leads to a crash at `json_family.cc:99`.

The crash manifests after many SET/DEL cycles on nested JSON data, typically in workloads that frequently create and delete complex JSON documents.
