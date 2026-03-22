# Solution: ScyllaDB #28200

## Fix
- **Issue:** https://github.com/scylladb/scylladb/issues/28200

## Root cause
In `streaming_task_impl::run`, a `coroutine::lambda` is used to wrap a lambda function for asynchronous execution. The `coroutine::lambda` internally stores a pointer to the lambda object. However, the lambda object's lifetime is tied to the local scope where it is created, and this scope ends before the streaming task coroutine actually runs the lambda.

The sequence is:
1. A lambda is created on the stack (or as a local variable)
2. `coroutine::lambda` is constructed with a pointer/reference to this lambda
3. The function returns or the local scope ends, destroying the original lambda
4. The streaming task coroutine resumes and tries to call the lambda through the dangling pointer
5. Use-after-free: reads from freed memory

## Fix description
The fix ensures the lambda's lifetime extends until the coroutine is done using it. This can be done by:

1. **Copying the lambda into the coroutine state** instead of keeping a pointer to it — e.g., capturing by value rather than by reference
2. **Moving the lambda into a longer-lived storage** (such as the coroutine frame itself) so it survives until the coroutine completes
3. **Using `coroutine::lambda` correctly** by ensuring the lambda outlives all uses of the `coroutine::lambda` wrapper

The fix modifies the streaming task implementation to either:
- Use `std::move` to transfer ownership of the lambda into the coroutine, or
- Replace `coroutine::lambda` with direct coroutine code that doesn't require an external lambda object

Key file: `streaming/stream_session.cc` or `streaming/streaming_task_impl.cc` (or equivalent file implementing the streaming task coroutine).

## How to apply
```bash
# Identify and checkout the fix commit from the issue
git log --oneline --all --grep="28200" | head -5
git checkout <fix-commit-hash>
git submodule update --init --recursive
./configure.py --mode=dev --enable-asan
ninja build/dev/scylla
```
