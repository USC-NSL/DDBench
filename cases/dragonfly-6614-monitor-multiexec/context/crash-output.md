# Crash Output

Obtained by running `./build-dbg/dragonfly --port 16379 --logtostderr --proactor_threads 1 --dbfilename="" --dir /tmp/data` and sending concurrent `MULTI/MONITOR/MONITOR/EXEC` pipelines via raw Redis protocol against the buggy build.

## Output

```
F20260403 11:33:39.185312    10 dragonfly_connection.cc:1917] Check failed: cc_ 
*** Check failure stack trace: ***
    @     0x5c66290745ab  google::LogMessage::Fail()
    @     0x5c66290744f1  google::LogMessage::SendToLog()
    @     0x5c6629073ca4  google::LogMessage::Flush()
    @     0x5c6629077c50  google::LogMessageFatal::~LogMessageFatal()
    @     0x5c6628d8deb3  facade::Connection::SendAsync()
    @     0x5c6628d8d68d  facade::Connection::SendMonitorMessageAsync()
    @     0x5c66282866f9  dfly::(anonymous namespace)::DispatchMonitor()::{lambda()#1}::operator()()
    @     0x5c66282a05a6  util::ProactorPool::DispatchBrief<>()::{lambda()#1}::operator()()
    @     0x5c66282d81ea  fu2::abi_400::detail::invocation::invoke<>()
    @     0x5c66282d33e9  fu2::abi_400::detail::type_erasure::invocation_table::function_trait<>::internal_invoker<>::invoke()
    @     0x5c662900ad4c  fu2::abi_400::detail::type_erasure::tables::vtable<>::invoke<>()
    @     0x5c662900adb1  fu2::abi_400::detail::type_erasure::erasure<>::invoke<>()
    @     0x5c662900adf0  fu2::abi_400::detail::type_erasure::invocation_table::operator_impl<>::operator()()
    @     0x5c6629024100  util::fb2::EpollProactor::MainLoop()
    @     0x5c6628f65221  util::fb2::ProactorDispatcher::Run()
    @     0x5c6628f7aa51  util::fb2::detail::(anonymous namespace)::DispatcherImpl::Run()
    @     0x5c6628f7a56d  util::fb2::detail::(anonymous namespace)::DispatcherImpl::DispatcherImpl()::{lambda()#1}::operator()()
    @     0x5c6628f81dfe  std::__invoke_impl<>()
    @     0x5c6628f81d20  std::__invoke<>()
    @     0x5c6628f81b61  std::invoke<>()
    @     0x5c6628f818a8  boost::context::detail::fiber_record<>::run()
    @     0x5c6628f814ca  boost::context::detail::fiber_entry<>()
    @     0x7671d3cb31f7  make_fcontext
*** SIGABRT received at time=1775216019 on cpu 0 ***
PC: @     0x7671d31e9b2c  (unknown)  pthread_kill
    @     0x5c66290d7863         64  absl::lts_20250512::WriteFailureInfo()
    @     0x5c66290d7ae7         96  absl::lts_20250512::AbslFailureSignalHandler()
    @     0x7671d3190330       3520  (unknown)
    @     0x7671d319027e         32  raise
    @     0x7671d31738ff        192  abort
    @     0x5c662907d9d7        176  google::DumpStackTraceAndExit()
    @     0x5c66290745ab         16  google::LogMessage::Fail()
    @     0x5c66290744f1        160  google::LogMessage::SendToLog()
    @     0x5c6629073ca4         80  google::LogMessage::Flush()
    @     0x5c6629077c50         32  google::LogMessageFatal::~LogMessageFatal()
    @     0x5c6628d8deb3        256  facade::Connection::SendAsync()
    @     0x5c6628d8d68d        144  facade::Connection::SendMonitorMessageAsync()
    @     0x5c66282866f9        256  dfly::(anonymous namespace)::DispatchMonitor()::{lambda()#1}::operator()()
    @     0x5c66282a05a6         32  util::ProactorPool::DispatchBrief<>()::{lambda()#1}::operator()()
    @     0x5c66282d81ea         32  fu2::abi_400::detail::invocation::invoke<>()
    @     0x5c66282d33e9         48  fu2::abi_400::detail::type_erasure::invocation_table::function_trait<>::internal_invoker<>::invoke()
    @     0x5c662900ad4c         80  fu2::abi_400::detail::type_erasure::tables::vtable<>::invoke<>()
    @     0x5c662900adb1         80  fu2::abi_400::detail::type_erasure::erasure<>::invoke<>()
    @     0x5c662900adf0         48  fu2::abi_400::detail::type_erasure::invocation_table::operator_impl<>::operator()()
    @     0x5c6629024100       1936  util::fb2::EpollProactor::MainLoop()
    @     0x5c6628f65221         48  util::fb2::ProactorDispatcher::Run()
    @     0x5c6628f7aa51        192  util::fb2::detail::(anonymous namespace)::DispatcherImpl::Run()
    @     0x5c6628f7a56d         80  util::fb2::detail::(anonymous namespace)::DispatcherImpl::DispatcherImpl()::{lambda()#1}::operator()()
    @     0x5c6628f81dfe         80  std::__invoke_impl<>()
    @     0x5c6628f81d20         80  std::__invoke<>()
    @     0x5c6628f81b61         80  std::invoke<>()
    @     0x5c6628f818a8         80  boost::context::detail::fiber_record<>::run()
    @     0x5c6628f814ca         48  boost::context::detail::fiber_entry<>()
    @     0x7671d3cb31f7  (unknown)  make_fcontext

Process exited with code 134 (SIGABRT).
```
