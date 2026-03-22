# Reproduce: Nomad #27567

## Prerequisites
- Nomad v1.11.2 running in dev mode (see setup.md)

## Step 1: Create a system job with deployments

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

  group "test" {
    task "test" {
      driver = "docker"

      config {
        image = "busybox:1.36"
        command = "/bin/sh"
        args = ["-c", "while true; do sleep 3600; done"]
      }

      resources {
        cpu    = 100
        memory = 64
      }
    }
  }
}
```

## Step 2: Submit the job

```bash
nomad job run system-job.nomad.hcl
```

## Step 3: Trigger an evaluation

Update the job to trigger a new deployment and evaluation:
```bash
# Modify the job slightly (e.g., change memory)
sed -i 's/memory = 64/memory = 128/' system-job.nomad.hcl
nomad job run system-job.nomad.hcl
```

Or force an evaluation:
```bash
nomad job eval -force-reschedule test-system
```

## Step 4: Observe the panic

Check the Nomad server logs:
```bash
# If running in foreground, the panic will be printed to stderr
# If running as a service:
journalctl -u nomad | grep -A 20 "panic"

# Or in Docker:
docker logs nomad 2>&1 | grep -A 20 "panic"
```

## Expected result (bug present)

The scheduler panics with:
```
panic: runtime error: invalid memory address or nil pointer dereference
[signal SIGSEGV: segmentation violation code=0x1 addr=0x... pc=0x...]

goroutine NNN [running]:
github.com/hashicorp/nomad/scheduler.(*SystemScheduler).process(...)
```

## Expected result (bug absent)

The job is successfully updated and the new deployment proceeds without any panic. The evaluation is processed normally.

## Notes
- The panic is deterministic once the right conditions are met (system job with update stanza triggering a new eval).
- In dev mode, a single panic may crash the entire agent.
- In a production cluster, the eval may be retried on different servers, each of which panics.
