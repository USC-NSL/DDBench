# Crash Output

Obtained by running `./build-dbg/dragonfly --port 16379 --logtostderr --proactor_threads 1 --dbfilename=""`, then `redis-cli -p 16379 FT.CREATE myidx ON HASH PREFIX 1 doc: SCHEMA score NUMERIC`, then `redis-cli -p 16379 HSET doc:1 score inf` against the buggy build.

## Output

```
F20260403 11:49:03.445602    11 range_tree.cc:84] Check failed: std::isfinite(value)
*** Check failure stack trace: ***
    @     0x5f1d70e44ead  google::LogMessage::Fail()
    @     0x5f1d70e44df3  google::LogMessage::SendToLog()
    @     0x5f1d70e445a6  google::LogMessage::Flush()
    @     0x5f1d70e48552  google::LogMessageFatal::~LogMessageFatal()
    @     0x5f1d70aeacfe  dfly::search::RangeTree::Add()
    @     0x5f1d70a103fd  dfly::search::RangeTreeAdapter::Add()
    @     0x5f1d70a0c0bb  dfly::search::NumericIndex::Add()
    @     0x5f1d709c429b  dfly::search::FieldIndices::Add()::{lambda()#1}::operator()<>()
    @     0x5f1d709c452b  dfly::search::FieldIndices::Add()
    @     0x5f1d70424ba1  dfly::ShardDocIndex::AddDoc()
    @     0x5f1d7042ab71  dfly::ShardDocIndices::AddDoc()
    @     0x5f1d6ffc3f95  dfly::(anonymous namespace)::OpSet()
    @     0x5f1d6ffc7bf0  dfly::(anonymous namespace)::CmdHSet()::{lambda()#1}::operator()()
    @     0x5f1d6ffd11f1  dfly::Transaction::ScheduleSingleHopT<>()::{lambda()#1}::operator()()
    @     0x5f1d6ffdb94d  std::__invoke_impl<>()
    @     0x5f1d6ffda9d3  std::__invoke<>()
    @     0x5f1d6ffd8e84  std::invoke<>()
    @     0x5f1d6ffd72b9  absl::lts_20250512::functional_internal::InvokeObject<>()
    @     0x5f1d708d1298  absl::lts_20250512::FunctionRef<>::operator()()
    @     0x5f1d708bd099  dfly::Transaction::RunCallback()
    @     0x5f1d708c25cc  dfly::Transaction::ScheduleInShard()
    @     0x5f1d708be224  dfly::Transaction::ScheduleInternal()
    @     0x5f1d708bf980  dfly::Transaction::Execute()
    @     0x5f1d708bf177  dfly::Transaction::ScheduleSingleHop()
    @     0x5f1d6ffd128b  dfly::Transaction::ScheduleSingleHopT<>()
    @     0x5f1d6ffc7d93  dfly::(anonymous namespace)::CmdHSet()
*** SIGABRT received at time=1775216927 on cpu 0 ***
PC: @     0x7c85d89bcb2c  (unknown)  pthread_kill
    @     0x5f1d70ea8133         64  absl::lts_20250512::WriteFailureInfo()
    @     0x5f1d70ea83b7         96  absl::lts_20250512::AbslFailureSignalHandler()
    @     0x7c85d8963330       3536  (unknown)
    @     0x7c85d896327e         32  raise
    @     0x7c85d89468ff        192  abort
    @     0x5f1d70e4e2d9        176  google::DumpStackTraceAndExit()
    @     0x5f1d70e44ead         16  google::LogMessage::Fail()
    @     0x5f1d70e44df3        160  google::LogMessage::SendToLog()
    @     0x5f1d70e445a6         80  google::LogMessage::Flush()
    @     0x5f1d70e48552         32  google::LogMessageFatal::~LogMessageFatal()
    @     0x5f1d70aeacfe        256  dfly::search::RangeTree::Add()
    @     0x5f1d70a103fd         80  dfly::search::RangeTreeAdapter::Add()
    @     0x5f1d70a0c0bb        128  dfly::search::NumericIndex::Add()
    @     0x5f1d709c429b        144  dfly::search::FieldIndices::Add()::{lambda()#1}::operator()<>()
    @     0x5f1d709c452b        208  dfly::search::FieldIndices::Add()
    @     0x5f1d70424ba1        128  dfly::ShardDocIndex::AddDoc()
    @     0x5f1d7042ab71        256  dfly::ShardDocIndices::AddDoc()
    @     0x5f1d6ffc3f95        640  dfly::(anonymous namespace)::OpSet()
    @     0x5f1d6ffc7bf0        128  dfly::(anonymous namespace)::CmdHSet()::{lambda()#1}::operator()()
    @     0x5f1d6ffd11f1         64  dfly::Transaction::ScheduleSingleHopT<>()::{lambda()#1}::operator()()

Error: Server closed the connection
Process exited with code 134 (SIGABRT).
```
