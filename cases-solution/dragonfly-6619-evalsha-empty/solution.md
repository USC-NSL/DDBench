# Solution: Dragonfly #6619

## Fix
- **PR:** https://github.com/dragonflydb/dragonfly/pull/6620
- **Commit:** `761387a51433a5becb06db2ac7bf7e9f18b832d2`

## Root cause
The EVALSHA command handler does not validate that the SHA argument is non-empty before using it. The assertion `!eval_args.sha.empty()` fails when an empty string is passed.

## Fix description
Add validation at the start of the EVALSHA handler: if SHA is empty, return `NOSCRIPT` error to the client.

## How to apply
```bash
git checkout 761387a51433a5becb06db2ac7bf7e9f18b832d2
git submodule update --init --recursive
./helio/blaze.sh -DCMAKE_BUILD_TYPE=Debug
```
