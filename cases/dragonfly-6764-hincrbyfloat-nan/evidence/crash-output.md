# Crash Output

Obtained by running `./build-dbg/dragonfly --port 16379 --logtostderr --proactor_threads 1 --dbfilename=""`, then `redis-cli -p 16379 HINCRBYFLOAT nonexist field nan` followed by `redis-cli -p 16379 HRANDFIELD nonexist 1` against the buggy build.

## Output

```
F20260403 11:43:53.441455    10 hset_family.cc:973] Check failed: lplen > 0 && lplen % 2 == 0
*** Check failure stack trace: ***
    @     0x56ebee78439d  google::LogMessage::Fail()
    @     0x56ebee7842e3  google::LogMessage::SendToLog()
    @     0x56ebee783a96  google::LogMessage::Flush()
    @     0x56ebee787a42  google::LogMessageFatal::~LogMessageFatal()
    @     0x56ebed94f5a5  dfly::(anonymous namespace)::CmdHRandField()::{lambda()#1}::operator()()
    @     0x56ebed957ef9  dfly::Transaction::ScheduleSingleHopT<>()::{lambda()#1}::operator()()
    @     0x56ebed96231b  std::__invoke_impl<>()
    @     0x56ebed961413  std::__invoke<>()
    @     0x56ebed95f90e  std::invoke<>()
    @     0x56ebed95de2d  absl::lts_20250512::functional_internal::InvokeObject<>()
    @     0x56ebee21bf84  absl::lts_20250512::FunctionRef<>::operator()()
    @     0x56ebee207db3  dfly::Transaction::RunCallback()
    @     0x56ebee20d2e6  dfly::Transaction::ScheduleInShard()
    @     0x56ebee208f3e  dfly::Transaction::ScheduleInternal()
    @     0x56ebee20a69a  dfly::Transaction::Execute()
    @     0x56ebee209e91  dfly::Transaction::ScheduleSingleHop()
    @     0x56ebed957fce  dfly::Transaction::ScheduleSingleHopT<>()
    @     0x56ebed94fef3  dfly::(anonymous namespace)::CmdHRandField()
    @     0x56ebed8f87e5  fu2::abi_400::detail::invocation::invoke<>()
    @     0x56ebed8f4d5a  fu2::abi_400::detail::type_erasure::invocation_table::function_trait<>::internal_invoker<>::invoke()
    @     0x56ebed9dcb3b  fu2::abi_400::detail::type_erasure::tables::vtable<>::invoke<>()
    @     0x56ebed9dcbd4  fu2::abi_400::detail::type_erasure::erasure<>::invoke<>()
    @     0x56ebed9dcc52  fu2::abi_400::detail::type_erasure::invocation_table::operator_impl<>::operator()()
    @     0x56ebed9d82f7  dfly::CommandId::Invoke()
    @     0x56ebed98b5df  dfly::Service::InvokeCmd()
    @     0x56ebed98ab60  dfly::Service::DispatchCommand()
    @     0x56ebee496ebb  facade::Connection::ParseRedis()::{lambda()#1}::operator()()
    @     0x56ebee4a6d8e  std::__invoke_impl<>()
    @     0x56ebee4a62b5  std::__invoke<>()
    @     0x56ebee4a5678  std::invoke<>()
    @     0x56ebee4a479c  absl::lts_20250512::functional_internal::InvokeObject<>()
    @     0x56ebee4aad90  absl::lts_20250512::FunctionRef<>::operator()()
*** SIGABRT received at time=1775216618 on cpu 0 ***
PC: @     0x75d1feff5b2c  (unknown)  pthread_kill
    @     0x56ebee7e7655         64  absl::lts_20250512::WriteFailureInfo()
    @     0x56ebee7e78d9         96  absl::lts_20250512::AbslFailureSignalHandler()
    @     0x75d1fef9c330       3504  (unknown)
    @     0x75d1fef9c27e         32  raise
    @     0x75d1fef7f8ff        192  abort
    @     0x56ebee78d7c9        176  google::DumpStackTraceAndExit()
    @     0x56ebee78439d         16  google::LogMessage::Fail()
    @     0x56ebee7842e3        160  google::LogMessage::SendToLog()
    @     0x56ebee783a96         80  google::LogMessage::Flush()
    @     0x56ebee787a42         32  google::LogMessageFatal::~LogMessageFatal()
    @     0x56ebed94f5a5        944  dfly::(anonymous namespace)::CmdHRandField()::{lambda()#1}::operator()()
    @     0x56ebed957ef9         96  dfly::Transaction::ScheduleSingleHopT<>()::{lambda()#1}::operator()()
    @     0x56ebed96231b         64  std::__invoke_impl<>()
    @     0x56ebed961413         64  std::__invoke<>()
    @     0x56ebed95f90e         64  std::invoke<>()
    @     0x56ebed95de2d         96  absl::lts_20250512::functional_internal::InvokeObject<>()
    @     0x56ebee21bf84         64  absl::lts_20250512::FunctionRef<>::operator()()
    @     0x56ebee207db3        240  dfly::Transaction::RunCallback()
    @     0x56ebee20d2e6        448  dfly::Transaction::ScheduleInShard()
    @     0x56ebee208f3e        336  dfly::Transaction::ScheduleInternal()
    @     0x56ebee20a69a         64  dfly::Transaction::Execute()
    @     0x56ebee209e91         48  dfly::Transaction::ScheduleSingleHop()
    @     0x56ebed957fce        128  dfly::Transaction::ScheduleSingleHopT<>()
    @     0x56ebed94fef3        336  dfly::(anonymous namespace)::CmdHRandField()

Error: Server closed the connection
Process exited with code 134 (SIGABRT).
```
