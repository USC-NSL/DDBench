# Solution: NATS Server #7726

## Fix
- **PR:** https://github.com/nats-io/nats-server/pull/7725
- **Commit:** `6aded805ec9625b20ee50ded3b63135d5fe3d0a8`

## Root cause
The subject tree intersection logic does not handle mixed wildcard/literal combinations correctly. When a consumer has both a wildcard filter (e.g., `events.*`) and a literal filter (e.g., `events.specific`), the intersection algorithm incorrectly concludes that the literal subject does not match, because the wildcard path subsumes it in the tree structure.

## Fix description
Fix the subject tree intersection to properly handle mixed filter types. The PR improves the intersection algorithm so that literal subjects are correctly recognized as matching even when a wildcard pattern also covers the same namespace.

## How to apply
```bash
git checkout 6aded805ec9625b20ee50ded3b63135d5fe3d0a8
go build -o nats-server .
```
