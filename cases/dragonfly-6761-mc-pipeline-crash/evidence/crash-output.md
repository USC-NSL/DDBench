# Crash Output

Obtained by running `./build-dbg/dragonfly --port 16379 --memcached_port=11211 --logtostderr --proactor_threads 1 --dbfilename="" --max_bulk_len=1048576` and then `printf "get nokey\r\nversion\r\n" | nc 127.0.0.1 11211` against the buggy build.

## Output

```
F20260403 11:42:24.925774    10 dragonfly_connection.cc:2286] Check failed: is_head 
*** Check failure stack trace: ***
    @     0x587fc9daa77d  google::LogMessage::Fail()
    @     0x587fc9daa6c3  google::LogMessage::SendToLog()
    @     0x587fc9da9e76  google::LogMessage::Flush()
    @     0x587fc9dade22  google::LogMessageFatal::~LogMessageFatal()
    @     0x587fc9ac64c4  facade::Connection::ExecuteMCBatch()
    @     0x587fc9abde8d  facade::Connection::ParseMemcache()
    @     0x587fc9ac86ec  facade::Connection::IoLoopV2()
    @     0x587fc9abbb6b  facade::Connection::ConnectionFlow()
    @     0x587fc9ab9566  facade::Connection::HandleRequests()
    @     0x587fc9cd0775  util::ListenerInterface::RunSingleConnection()
    @     0x587fc9cce2f6  util::ListenerInterface::RunAcceptLoop()::{lambda()#1}::operator()()::{lambda()#1}::operator()()
    @     0x587fc9cd813a  std::__invoke_impl<>()
    @     0x587fc9cd7010  std::__invoke<>()
    @     0x587fc9cd5b10  std::__apply_impl<>()
    @     0x587fc9cd5b4a  std::apply<>()
    @     0x587fc9cd5bcf  util::fb2::detail::WorkerFiberImpl<>::run_()
*** SIGABRT received at time=1775216544 on cpu 0 ***
PC: @     0x75ba9cc8bb2c  (unknown)  pthread_kill
    @     0x587fc9e0da35         64  absl::lts_20250512::WriteFailureInfo()
    @     0x587fc9e0dcb9         96  absl::lts_20250512::AbslFailureSignalHandler()
    @     0x75ba9cc32330       3504  (unknown)
    @     0x75ba9cc3227e         32  raise
    @     0x75ba9cc158ff        192  abort
    @     0x587fc9db3ba9        176  google::DumpStackTraceAndExit()
    @     0x587fc9daa77d         16  google::LogMessage::Fail()
    @     0x587fc9daa6c3        160  google::LogMessage::SendToLog()
    @     0x587fc9da9e76         80  google::LogMessage::Flush()
    @     0x587fc9dade22         32  google::LogMessageFatal::~LogMessageFatal()
    @     0x587fc9ac64c4        192  facade::Connection::ExecuteMCBatch()
    @     0x587fc9abde8d         48  facade::Connection::ParseMemcache()
    @     0x587fc9ac86ec        368  facade::Connection::IoLoopV2()
    @     0x587fc9abbb6b        352  facade::Connection::ConnectionFlow()
    @     0x587fc9ab9566        656  facade::Connection::HandleRequests()
    @     0x587fc9cd0775        288  util::ListenerInterface::RunSingleConnection()
    @     0x587fc9cce2f6         48  util::ListenerInterface::RunAcceptLoop()::{lambda()#1}::operator()()::{lambda()#1}::operator()()
    @     0x587fc9cd813a         32  std::__invoke_impl<>()
    @     0x587fc9cd7010         32  std::__invoke<>()
    @     0x587fc9cd5b10         32  std::__apply_impl<>()
    @     0x587fc9cd5b4a         48  std::apply<>()
    @     0x587fc9cd5bcf        112  util::fb2::detail::WorkerFiberImpl<>::run_()
    @     0x587fc9cd4935         80  util::fb2::detail::WorkerFiberImpl<>::WorkerFiberImpl<>()::{lambda()#1}::operator()()
    @     0x587fc9cdf237         80  std::__invoke_impl<>()
    @     0x587fc9cdda6a         80  std::__invoke<>()
    @     0x587fc9cdb76d         80  std::invoke<>()
    @     0x587fc9cda248         80  boost::context::detail::fiber_record<>::run()
    @     0x587fc9cd8260         48  boost::context::detail::fiber_entry<>()
    @     0x75ba9d7551f7  (unknown)  make_fcontext

Process exited with code 134 (SIGABRT).
```
