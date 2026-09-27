# Crash Output

Obtained by running `./build-dbg/dragonfly --port 16379 --logtostderr --proactor_threads 1 --dbfilename=""` and then `redis-cli -p 16379 DEBUG POPULATE 100 prefix 0` against the buggy build.

## Output

```
*** SIGFPE received at time=1775216494 on cpu 0 ***
PC: @     0x5e1c3ff9bb4e  (unknown)  dfly::DebugCmd::DoPopulateBatch()
    @     0x5e1c40a84305         64  absl::lts_20250512::WriteFailureInfo()
    @     0x5e1c40a84589         96  absl::lts_20250512::AbslFailureSignalHandler()
    @     0x777687a21330       5024  (unknown)
    @     0x5e1c3ff94400         32  dfly::DebugCmd::PopulateRangeFiber()::{lambda()#1}::operator()()
    @     0x5e1c3ffb7ca4         32  std::__invoke_impl<>()
    @     0x5e1c3ffb343a         32  std::__invoke_r<>()
    @     0x5e1c3ffadfea         32  std::_Function_handler<>::_M_invoke()
    @     0x5e1c3faecd1e         32  std::function<>::operator()()
    @     0x5e1c4099c256        240  util::fb2::FiberQueue::Run()
    @     0x5e1c40552cc3         32  dfly::TaskQueue::Start()::{lambda()#1}::operator()()
    @     0x5e1c40553e7b         32  std::__invoke_impl<>()
    @     0x5e1c40553c00         32  std::__invoke<>()
    @     0x5e1c40553a0e         32  std::__apply_impl<>()
    @     0x5e1c40553a48         48  std::apply<>()
    @     0x5e1c40553ac5         96  util::fb2::detail::WorkerFiberImpl<>::run_()
    @     0x5e1c40553643         80  util::fb2::detail::WorkerFiberImpl<>::WorkerFiberImpl<>()::{lambda()#1}::operator()()
    @     0x5e1c405547bc         80  std::__invoke_impl<>()
    @     0x5e1c405545e7         80  std::__invoke<>()
    @     0x5e1c405544bd         80  std::invoke<>()
    @     0x5e1c40554268         80  boost::context::detail::fiber_record<>::run()
    @     0x5e1c40553fa0         48  boost::context::detail::fiber_entry<>()
    @     0x7776885441f7  (unknown)  make_fcontext

Error: Server closed the connection
Floating point exception (core dumped)
Process exited with code 136 (SIGFPE).
```
