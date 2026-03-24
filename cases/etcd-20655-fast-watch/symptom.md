# Symptom

High-frequency watch creation breaks etcd's reliable watch guarantee, causing events to be silently dropped. When watches are created rapidly in succession, a race condition in the watch subsystem causes some watches to miss events that occur during or shortly after their creation.

This violates etcd's core guarantee that watches deliver all events from the requested revision onward. The bug is reproduced on both `main` and `release-3.5` branches.
