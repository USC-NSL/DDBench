# Symptom

## Description

The Nomad scheduler panics with a nil pointer dereference when processing evaluations for system jobs that have deployments. The panic occurs inside the scheduler goroutine, and depending on the Nomad version and configuration, it may crash the Nomad server process or cause the evaluation to be retried repeatedly (crashing each time).

## Observable behavior

- Nomad server logs show a panic with a stack trace:
  ```
  panic: runtime error: invalid memory address or nil pointer dereference
  ```
- The panic occurs in the system scheduler's deployment handling code path.
- The panic is triggered when processing evaluations (evals) for system jobs.
- System jobs that use the `update` stanza (which enables deployments) are the trigger.
- The Nomad server may become unstable, with the leader repeatedly crashing and re-electing.
- In a multi-server cluster, the crash can cascade as each server that becomes leader tries to process the same eval.
- Non-system jobs (service, batch) are not affected.

## Impact

System jobs with deployments become unschedulable. If any system job has pending evaluations, the scheduler panics, potentially causing cluster-wide instability.
