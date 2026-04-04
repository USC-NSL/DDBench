# Test Output

Obtained by running `go test -v -timeout 30s ./lib/routine/` against the buggy build.

## Output

```
=== RUN   TestManager
=== RUN   TestManager_StopAll
=== CONT  TestManager
=== CONT  TestManager_StopAll
2026-04-04T09:36:23.158Z [INFO]  TestManager_StopAll: started routine: routine=run1
2026-04-04T09:36:23.158Z [INFO]  TestManager_StopAll: started routine: routine=run2
2026-04-04T09:36:23.158Z [DEBUG] TestManager_StopAll: stopping routine: routine=run1
2026-04-04T09:36:23.158Z [DEBUG] TestManager_StopAll: stopping routine: routine=run2
2026-04-04T09:36:23.158Z [DEBUG] TestManager_StopAll: stopped routine: routine=run2
2026-04-04T09:36:23.158Z [DEBUG] TestManager_StopAll: stopped routine: routine=run1
--- PASS: TestManager_StopAll (0.03s)
2026-04-04T09:36:23.158Z [INFO]  TestManager: started routine: routine=run
2026-04-04T09:36:23.158Z [DEBUG] TestManager: stopping routine: routine=run
2026-04-04T09:36:23.158Z [DEBUG] TestManager: stopped routine: routine=run
2026-04-04T09:36:23.158Z [INFO]  TestManager: started routine: routine=run
2026-04-04T09:36:23.183Z [DEBUG] TestManager: stopping routine: routine=run
2026-04-04T09:36:23.183Z [DEBUG] TestManager: stopped routine: routine=run
2026-04-04T09:36:23.183Z [INFO]  TestManager: started routine: routine=run
2026-04-04T09:36:23.183Z [DEBUG] TestManager: stopped routine: routine=run
--- PASS: TestManager (0.05s)
PASS
ok  	github.com/hashicorp/consul/lib/routine	0.054s
```

All existing routine manager tests pass. No test covers the scenario where `Start` is called for a routine whose context was just cancelled but whose goroutine hasn't exited yet (the race window between context cancellation and `stoppedCh` closing).
