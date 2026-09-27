# Crash Output

Obtained by running `./build-dbg/dragonfly --port 16379 --memcached_port=11211 --max_bulk_len=1048576 --logtostderr --proactor_threads 1 --dbfilename="" --dir /tmp/data`, then `redis-cli -p 16379 SET bigkey "<16000 A characters>"`, then `echo -e "mg bigkey v\r\nquit\r\n" | nc 127.0.0.1 11211` against the buggy build.

## Output

```
F20260403 11:36:20.226082    10 reply_builder.cc:149] Check failed: expected_buffer_cap <= kMaxBufferSize (16039 vs. 8192) 
*** Check failure stack trace: ***
    @     0x6176630436ab  google::LogMessage::Fail()
    @     0x6176630435f1  google::LogMessage::SendToLog()
    @     0x617663042da4  google::LogMessage::Flush()
    @     0x617663046d50  google::LogMessageFatal::~LogMessageFatal()
    @     0x64420e7969e7  facade::SinkReplyBuilder::Flush()
    @     0x64420e79c171  facade::SinkReplyBuilder::WritePieces<>()
    @     0x64420e797830  facade::MCReplyBuilder::SendValue()
    @     0x64420e1bef24  dfly::(anonymous namespace)::MGetGeneric()::{lambda()#1}::operator()()
    @     0x64420e1c76c5  facade::ParsedCommand::ReplyWith<>()
    @     0x64420e1bf798  dfly::(anonymous namespace)::MGetGeneric()
    @     0x64420e1bfa88  dfly::(anonymous namespace)::CmdMGet()
    @     0x64420dbd844f  fu2::abi_400::detail::invocation::invoke<>()
    @     0x64420dbd49f4  fu2::abi_400::detail::type_erasure::invocation_table::function_trait<>::internal_invoker<>::invoke()
    @     0x64420dcbbcd5  fu2::abi_400::detail::type_erasure::tables::vtable<>::invoke<>()
    @     0x64420dcbbd6e  fu2::abi_400::detail::type_erasure::erasure<>::invoke<>()
    @     0x64420dcbbdec  fu2::abi_400::detail::type_erasure::invocation_table::operator_impl<>::operator()()
    @     0x64420dcb7463  dfly::CommandId::Invoke()
    @     0x64420dc6a7f9  dfly::Service::InvokeCmd()
    @     0x64420dc69d7a  dfly::Service::DispatchCommand()
    @     0x64420dc6c67f  dfly::Service::DispatchMC()
    @     0x64420e76f0f6  facade::Connection::ExecuteMCBatch()
    @     0x64420e766b2b  facade::Connection::ParseMemcache()
    @     0x64420e767a31  facade::Connection::IoLoop()
    @     0x64420e764861  facade::Connection::ConnectionFlow()
    @     0x64420e7623a4  facade::Connection::HandleRequests()
    @     0x64420e97b333  util::ListenerInterface::RunSingleConnection()
    @     0x64420e978eb4  util::ListenerInterface::RunAcceptLoop()::{lambda()#1}::operator()()::{lambda()#1}::operator()()
    @     0x64420e982cf8  std::__invoke_impl<>()
    @     0x64420e981bce  std::__invoke<>()
    @     0x64420e9806ce  std::__apply_impl<>()
    @     0x64420e980708  std::apply<>()
    @     0x64420e98078d  util::fb2::detail::WorkerFiberImpl<>::run_()
*** SIGABRT received at time=1775216160 on cpu 0 ***
PC: @     0x72f3f603db2c  (unknown)  pthread_kill
    @     0x64420eab5963         64  absl::lts_20250512::WriteFailureInfo()
    @     0x64420eab5be7         96  absl::lts_20250512::AbslFailureSignalHandler()
    @     0x72f3f5fe4330       3504  (unknown)
    @     0x72f3f5fe427e         32  raise
    @     0x72f3f5fc78ff        192  abort
    @     0x64420ea5bad7        176  google::DumpStackTraceAndExit()
    @     0x64420ea526ab         16  google::LogMessage::Fail()
    @     0x64420ea525f1        160  google::LogMessage::SendToLog()
    @     0x64420ea51da4         80  google::LogMessage::Flush()
    @     0x64420ea55d50         32  google::LogMessageFatal::~LogMessageFatal()
    @     0x64420e7969e7        176  facade::SinkReplyBuilder::Flush()
    @     0x64420e79c171        368  facade::SinkReplyBuilder::WritePieces<>()
    @     0x64420e797830        272  facade::MCReplyBuilder::SendValue()
    @     0x64420e1bef24        208  dfly::(anonymous namespace)::MGetGeneric()::{lambda()#1}::operator()()
    @     0x64420e1c76c5         80  facade::ParsedCommand::ReplyWith<>()
    @     0x64420e1bf798        432  dfly::(anonymous namespace)::MGetGeneric()
    @     0x64420e1bfa88         64  dfly::(anonymous namespace)::CmdMGet()
    @     0x64420dbd844f         64  fu2::abi_400::detail::invocation::invoke<>()
    @     0x64420dbd49f4         96  fu2::abi_400::detail::type_erasure::invocation_table::function_trait<>::internal_invoker<>::invoke()
    @     0x64420dcbbcd5        112  fu2::abi_400::detail::type_erasure::tables::vtable<>::invoke<>()
    @     0x64420dcbbd6e        112  fu2::abi_400::detail::type_erasure::erasure<>::invoke<>()
    @     0x64420dcbbdec         80  fu2::abi_400::detail::type_erasure::invocation_table::operator_impl<>::operator()()
    @     0x64420dcb7463         48  dfly::CommandId::Invoke()
    @     0x64420dc6a7f9        512  dfly::Service::InvokeCmd()
    @     0x64420dc69d7a        496  dfly::Service::DispatchCommand()
    @     0x64420dc6c67f        528  dfly::Service::DispatchMC()
    @     0x64420e76f0f6        192  facade::Connection::ExecuteMCBatch()
    @     0x64420e766b2b         48  facade::Connection::ParseMemcache()
    @     0x64420e767a31        320  facade::Connection::IoLoop()
    @     0x64420e764861        352  facade::Connection::ConnectionFlow()
    @     0x64420e7623a4        640  facade::Connection::HandleRequests()
    @     0x64420e97b333        288  util::ListenerInterface::RunSingleConnection()

Process exited with code 134 (SIGABRT).
```
