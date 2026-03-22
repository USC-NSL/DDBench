# Verification: Nomad #27567

## Test procedure

1. Start Nomad in dev mode:
   ```bash
   ./nomad agent -dev > nomad.log 2>&1 &
   NOMAD_PID=$!
   sleep 5
   ```

2. Create and submit a system job with deployment:
   ```bash
   cat > system-job.nomad.hcl <<'EOF'
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

   ./nomad job run system-job.nomad.hcl
   sleep 5
   ```

3. Trigger an update to create a new eval:
   ```bash
   sed 's/memory = 64/memory = 128/' system-job.nomad.hcl > system-job-v2.nomad.hcl
   ./nomad job run system-job-v2.nomad.hcl
   sleep 10
   ```

4. Check for panic:
   ```bash
   if grep -q "panic:" nomad.log; then
       echo "FAIL: Bug is present — scheduler panicked"
       grep -A 10 "panic:" nomad.log
   elif kill -0 $NOMAD_PID 2>/dev/null; then
       echo "PASS: Bug is fixed — no scheduler panic, process still running"
   else
       echo "FAIL: Process died (check nomad.log for details)"
   fi
   ```

5. Verify the job is running correctly:
   ```bash
   STATUS=$(./nomad job status test-system 2>/dev/null | grep "Status" | head -1 | awk '{print $NF}')
   if [ "$STATUS" = "running" ]; then
       echo "PASS: Job is running successfully"
   else
       echo "INCONCLUSIVE: Job status is $STATUS"
   fi
   ```

6. Cleanup:
   ```bash
   ./nomad job stop -purge test-system 2>/dev/null
   kill $NOMAD_PID 2>/dev/null
   ```

## Verdict criteria
- **FAIL (bug present):** Nomad server log contains a `panic: runtime error: invalid memory address or nil pointer dereference` in the system scheduler.
- **PASS (bug fixed):** No panic in logs, the system job update is processed normally, and the Nomad server process remains running.
