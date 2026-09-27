# Crash Output

Obtained by running `./build-dbg/dragonfly --port 16379 --logtostderr --proactor_threads 1 --dbfilename="" --dir /tmp/data` and then `redis-cli -p 16379 EVALSHA "" 0` against the buggy build.

## Output

```
F20260403 11:34:38.961018    10 main_service.cc:2207] Check failed: !eval_args.sha.empty() 
*** Check failure stack trace: ***
    @     0x56c6fceeb5bb  google::LogMessage::Fail()
    @     0x56c6fceeb501  google::LogMessage::SendToLog()
    @     0x56c6fceeacb4  google::LogMessage::Flush()
    @     0x56c6fceeec60  google::LogMessageFatal::~LogMessageFatal()
    @     0x56c6fc10dcaf  dfly::Service::EvalInternal()
    @     0x56c6fc10d1e6  dfly::Service::CallSHA()
    @     0x56c6fc10cefa  dfly::Service::EvalSha()
    @     0x56c6fc114236  dfly::Service::Register()::{lambda()#4}::operator()()
    @     0x56c6fc1425a6  fu2::abi_400::detail::invocation::invoke<>()
    @     0x56c6fc13c2a8  fu2::abi_400::detail::type_erasure::invocation_table::function_trait<>::internal_invoker<>::invoke()
    @     0x56c6fc15a58b  fu2::abi_400::detail::type_erasure::tables::vtable<>::invoke<>()
    @     0x56c6fc15a624  fu2::abi_400::detail::type_erasure::erasure<>::invoke<>()
    @     0x56c6fc15a6a2  fu2::abi_400::detail::type_erasure::invocation_table::operator_impl<>::operator()()
    @     0x56c6fc155d0b  dfly::CommandId::Invoke()
    @     0x56c6fc108e67  dfly::Service::InvokeCmd()
    @     0x56c6fc108580  dfly::Service::DispatchCommand()
    @     0x56c6fcbff485  facade::Connection::ParseRedis()::{lambda()#1}::operator()()
    @     0x56c6fcc0f2b4  std::__invoke_impl<>()
    @     0x56c6fcc0e7db  std::__invoke<>()
    @     0x56c6fcc0db9e  std::invoke<>()
    @     0x56c6fcc0ccc2  absl::lts_20250512::functional_internal::InvokeObject<>()
    @     0x56c6fcc1327c  absl::lts_20250512::FunctionRef<>::operator()()
    @     0x56c6fcbff335  facade::Connection::DispatchSingle()
    @     0x56c6fcbffaeb  facade::Connection::ParseRedis()
    @     0x56c6fcbfdb84  facade::Connection::ConnectionFlow()
    @     0x56c6fcbfb8f4  facade::Connection::HandleRequests()
    @     0x56c6fce1423f  util::ListenerInterface::RunSingleConnection()
    @     0x56c6fce11dc0  util::ListenerInterface::RunAcceptLoop()::{lambda()#1}::operator()()::{lambda()#1}::operator()()
    @     0x56c6fce1bc04  std::__invoke_impl<>()
    @     0x56c6fce1aada  std::__invoke<>()
    @     0x56c6fce195da  std::__apply_impl<>()
    @     0x56c6fce19614  std::apply<>()
*** SIGABRT received at time=1775216079 on cpu 0 ***
PC: @     0x7707c37acb2c  (unknown)  pthread_kill
    @     0x56c6fcf4e873         64  absl::lts_20250512::WriteFailureInfo()
    @     0x56c6fcf4eaf7         96  absl::lts_20250512::AbslFailureSignalHandler()
    @     0x7707c3753330       3536  (unknown)
    @     0x7707c375327e         32  raise
    @     0x7707c37368ff        192  abort
    @     0x56c6fcef49e7        176  google::DumpStackTraceAndExit()
    @     0x56c6fceeb5bb         16  google::LogMessage::Fail()
    @     0x56c6fceeb501        160  google::LogMessage::SendToLog()
    @     0x56c6fceeacb4         80  google::LogMessage::Flush()
    @     0x56c6fceeec60         32  google::LogMessageFatal::~LogMessageFatal()
    @     0x56c6fc10dcaf        640  dfly::Service::EvalInternal()
    @     0x56c6fc10d1e6        256  dfly::Service::CallSHA()
    @     0x56c6fc10cefa        176  dfly::Service::EvalSha()
    @     0x56c6fc114236         64  dfly::Service::Register()::{lambda()#4}::operator()()
    @     0x56c6fc1425a6         64  fu2::abi_400::detail::invocation::invoke<>()
    @     0x56c6fc13c2a8         96  fu2::abi_400::detail::type_erasure::invocation_table::function_trait<>::internal_invoker<>::invoke()
    @     0x56c6fc15a58b        112  fu2::abi_400::detail::type_erasure::tables::vtable<>::invoke<>()
    @     0x56c6fc15a624        112  fu2::abi_400::detail::type_erasure::erasure<>::invoke<>()
    @     0x56c6fc15a6a2         80  fu2::abi_400::detail::type_erasure::invocation_table::operator_impl<>::operator()()
    @     0x56c6fc155d0b         48  dfly::CommandId::Invoke()
    @     0x56c6fc108e67        448  dfly::Service::InvokeCmd()
    @     0x56c6fc108580        496  dfly::Service::DispatchCommand()
    @     0x56c6fcbff485        128  facade::Connection::ParseRedis()::{lambda()#1}::operator()()
    @     0x56c6fcc0f2b4         32  std::__invoke_impl<>()
    @     0x56c6fcc0e7db         32  std::__invoke<>()
    @     0x56c6fcc0db9e         32  std::invoke<>()
    @     0x56c6fcc0ccc2         48  absl::lts_20250512::functional_internal::InvokeObject<>()
    @     0x56c6fcc1327c         32  absl::lts_20250512::FunctionRef<>::operator()()
    @     0x56c6fcbff335        272  facade::Connection::DispatchSingle()
    @     0x56c6fcbffaeb        240  facade::Connection::ParseRedis()
    @     0x56c6fcbfdb84        352  facade::Connection::ConnectionFlow()
    @     0x56c6fcbfb8f4        640  facade::Connection::HandleRequests()

Error: Server closed the connection
Process exited with code 134 (SIGABRT).
```
