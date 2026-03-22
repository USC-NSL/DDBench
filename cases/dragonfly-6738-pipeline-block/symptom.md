# Symptom: Dragonfly #6738

`BRPOPLPUSH` (or `BLMOVE`) does not get woken up when `RPUSH` is executed inside a Lua `EVAL` script on the source list.

A client waiting on `BRPOPLPUSH src dst 5` will wait the full 5-second timeout and return `nil`, even though another client successfully pushed an element to `src` via `EVAL "redis.call('RPUSH', KEYS[1], ARGV[1])" 1 src value`.

The same `RPUSH` executed outside of `EVAL` correctly wakes the blocking consumer immediately.

This means Lua scripts that push to lists fail to trigger wake-up notifications for blocked consumers, causing timeouts and missed messages in producer-consumer patterns.
