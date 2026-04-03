# Symptom

After deleting a key in etcd, subsequent reads may still return the deleted key's value. This violates linearizability: a client that successfully deletes a key can immediately read it back as if the delete never happened.

## Observable behavior

- A key is deleted from etcd (e.g., via `etcdctl del`), and the delete is acknowledged as successful.
- Immediately after the delete, reading the same key returns the old value as if the delete never happened.
- In a running etcd cluster this surfaces as: deleted users remaining authenticatable, removed cluster members still appearing in membership queries, or deleted keys returning stale values.
- The stale read resolves on its own after a short interval, making the bug intermittent and timing-dependent.

