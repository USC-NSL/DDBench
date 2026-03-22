# Solution: Nomad #27567

## Fix
- **Issue:** https://github.com/hashicorp/nomad/issues/27567
- **Fix PR:** https://github.com/hashicorp/nomad/pull/27571
- **Fix commit:** `f95371693165852d0d58dca5b178a23c34d93819`

## Root cause

In the system scheduler's evaluation processing code, the deployment object is accessed without a nil check. For system jobs, deployments may or may not exist depending on the job's update configuration and the current state. When the scheduler processes an eval for a system job and tries to access the deployment, it dereferences a nil pointer if no active deployment exists for that job version.

The code path is:
1. System scheduler receives an eval for a system job.
2. It looks up the deployment associated with the job.
3. It accesses fields on the deployment object (e.g., `deployment.StatusDescription`) without checking if `deployment` is nil.
4. If there is no active deployment, the nil dereference causes a panic.

This can happen when:
- A system job has an `update` stanza but no deployment is currently active.
- A deployment was completed or cancelled but a new eval is triggered (e.g., by a node event).
- The deployment state is inconsistent between the state store and the scheduler's view.

## Fix description

The fix adds a nil check for the deployment object before accessing its fields in the system scheduler's eval processing code.

## Files changed

- **`scheduler/system_sched.go`** — Added nil check before dereferencing the deployment pointer:
  ```go
  // Before (buggy):
  if deployment.StatusDescription == structs.DeployStatusDescriptionPaused {
      // ...
  }

  // After (fixed):
  if deployment != nil && deployment.StatusDescription == structs.DeployStatusDescriptionPaused {
      // ...
  }
  ```

## How to apply the fix
```bash
cd nomad
git checkout f95371693165852d0d58dca5b178a23c34d93819
make dev
# Binary at ./bin/nomad
```

Or upgrade to Nomad >= 1.11.3.
