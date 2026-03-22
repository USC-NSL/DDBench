# Reproduce: Nomad #27567

## Prerequisites
- Nomad v1.11.2 running in dev mode (see setup.md)

## Step 1: Create a system job with multiple task groups

The panic requires a system job with **multiple task groups** where at least one group has no feasible candidate nodes. When a deployment completes successfully with mixed nil/non-nil task group deployment states, a subsequent evaluation dereferences the nil entry.

Create a file `system-job.nomad.hcl`:
```hcl
job "test-system" {
  type = "system"

  update {
    max_parallel     = 1
    min_healthy_time = "10s"
    healthy_deadline = "5m"
    auto_revert      = true
  }

  # Group that will succeed on any node
  group "primary" {
    task "test" {
      driver = "exec"

      config {
        command = "/bin/sleep"
        args    = ["3600"]
      }

      resources {
        cpu    = 100
        memory = 64
      }
    }
  }

  # Group constrained to nodes that don't exist — produces nil deployment state
  group "constrained" {
    constraint {
      attribute = "${node.unique.name}"
      value     = "nonexistent-node-xyz"
    }

    task "test2" {
      driver = "exec"

      config {
        command = "/bin/sleep"
        args    = ["3600"]
      }

      resources {
        cpu    = 100
        memory = 64
      }
    }
  }
}
```

## Step 2: Submit the job and wait for deployment

```bash
nomad job run system-job.nomad.hcl
```

Wait for the deployment to complete. The "primary" group will place successfully, while the "constrained" group will have no feasible nodes (producing a nil deployment state entry). The deployment may still complete as "successful" because the constrained group has 0 desired allocations.

```bash
# Wait for deployment to finish
sleep 30
nomad job status test-system
```

## Step 3: Update the job to remove the constraint

This creates a new evaluation that references the old deployment with the nil task group state:
```bash
# Remove the constraint so the constrained group now has feasible nodes
cat > system-job-v2.nomad.hcl <<'EOF'
job "test-system" {
  type = "system"

  update {
    max_parallel     = 1
    min_healthy_time = "10s"
    healthy_deadline = "5m"
    auto_revert      = true
  }

  group "primary" {
    task "test" {
      driver = "exec"
      config {
        command = "/bin/sleep"
        args    = ["3600"]
      }
      resources {
        cpu    = 100
        memory = 128
      }
    }
  }

  group "constrained" {
    task "test2" {
      driver = "exec"
      config {
        command = "/bin/sleep"
        args    = ["3600"]
      }
      resources {
        cpu    = 100
        memory = 64
      }
    }
  }
}
EOF

nomad job run system-job-v2.nomad.hcl
sleep 10
```

## Step 4: Observe the panic

Check the Nomad server logs:
```bash
# If running in foreground, the panic will be printed to stderr
# If running as a service:
journalctl -u nomad | grep -A 20 "panic"

# Or check the log file directly:
grep -A 20 "panic:" nomad.log
```

## Expected result (bug present)

The scheduler panics with:
```
panic: runtime error: invalid memory address or nil pointer dereference
[signal SIGSEGV: segmentation violation code=0x1 addr=0x... pc=0x...]

goroutine NNN [running]:
github.com/hashicorp/nomad/scheduler.(*SystemScheduler).process(...)
```

The panic occurs when the scheduler processes the new evaluation and looks up the previous deployment state for the "constrained" task group, which is nil.

## Expected result (bug absent)

The job is successfully updated and the new deployment proceeds without any panic. The evaluation is processed normally and both task groups are scheduled.

## Notes
- The key trigger is: a deployment with mixed nil/non-nil `TaskGroups` entries, followed by a new eval when previously infeasible nodes become feasible.
- In dev mode, a single panic may crash the entire agent.
- In a production cluster, the eval may be retried on different servers, each of which panics.
