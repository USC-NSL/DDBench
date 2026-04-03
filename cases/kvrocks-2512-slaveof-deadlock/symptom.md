# Symptom

When a Kvrocks instance receives rapid successive `SLAVEOF` commands pointing to different masters, the server deadlocks and becomes completely unresponsive. No error messages appear in the logs; the process simply hangs.

## Observable behavior
- After issuing two or more `SLAVEOF` commands in quick succession (switching between different masters), the Kvrocks instance stops responding to all commands, including `PING`.
- The server process remains running but is completely unresponsive. No crash, no error log, no timeout message.
- The deadlock is permanent once triggered. Restarting the Kvrocks process is the only recovery.
- The issue is reliably triggered by rapidly switching masters (e.g., `SLAVEOF host1 port1` immediately followed by `SLAVEOF host2 port2`).

