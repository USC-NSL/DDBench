# Test Output

Obtained by running concurrent `XREADGROUP GROUP mygroup consumerN BLOCK 5000 COUNT 1 STREAMS mystream >` commands from multiple clients while a producer calls `XADD mystream * key valueN` rapidly. A raw socket approach detects when more than one RESP response arrives per command.

## Output

```
Running double-response detection (raw socket approach)...
DOUBLE_RESPONSE_ERRORS=41
  consumer2 round 0: double response detected
  consumer1 round 0: double response detected
  consumer3 round 0: double response detected
  consumer2 round 1: double response detected
  consumer1 round 1: double response detected

FAIL: Bug is present — 41 double responses detected across consumers
```
