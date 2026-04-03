# Crash Output

Obtained by running `./build-dbg/dragonfly --port 16379 --logtostderr --proactor_threads 1 --dbfilename=""`, then `redis-cli -p 16379 LPUSH mylist 3 2 1`, `redis-cli -p 16379 PEXPIRE mylist 500`, `redis-cli -p 16379 SORT mylist STORE mylist`, and waiting for the expiry cycle against the buggy build.

## Output

```
F20260403 11:45:32.537222    10 db_slice.cc:1163] Inconsistent state, entry mylist leave stale expiration: 5490
*** Check failure stack trace: ***
    @     0x5acb085aa79d  google::LogMessage::Fail()
    @     0x5acb085aa6e3  google::LogMessage::SendToLog()
    @     0x5acb085a9e96  google::LogMessage::Flush()
    @     0x5acb085a9c11  google::LogMessage::~LogMessage()
    @     0x5acb07f57d0f  dfly::DbSlice::AddOrUpdateInternal()
    @     0x5acb07f57eb5  dfly::DbSlice::AddOrUpdate()
    @     0x5acb076ee48d  dfly::OpStore<>()
    @     0x5acb076e8d3c  dfly::SortVisitor::operator()<>()::{lambda()#1}::operator()()
    @     0x5acb076fd3f7  std::__invoke_impl<>()
    @     0x5acb076fa538  std::__invoke<>()
    @     0x5acb076f69ea  std::invoke<>()
    @     0x5acb076f2fd5  absl::lts_20250512::functional_internal::InvokeObject<>()
    @     0x5acb0803bc06  absl::lts_20250512::FunctionRef<>::operator()()
    @     0x5acb08027a5b  dfly::Transaction::RunCallback()
    @     0x5acb08026ecc  dfly::Transaction::RunInShard()
    @     0x5acb07ad31cd  dfly::EngineShard::PollExecution()::{lambda()#1}::operator()()
    @     0x5acb07ad3a12  dfly::EngineShard::PollExecution()
    @     0x5acb0802afe5  dfly::Transaction::DispatchHop()
    @     0x5acb0802a34e  dfly::Transaction::Execute()
    @     0x5acb076e937b  dfly::SortVisitor::operator()<>()
    @     0x5acb076e402e  std::__invoke_impl<>()
    @     0x5acb076de73a  std::__invoke<>()
    @     0x5acb076d7e36  std::__detail::__variant::__gen_vtable_impl<>::__visit_invoke()
    @     0x5acb076d7f60  std::__do_visit<>()
    @     0x5acb076d7fd7  std::visit<>()
    @     0x5acb076a6542  dfly::SortGeneric()
    @     0x5acb076a6bf7  dfly::GenericFamily::Sort()
*** SIGABRT received at time=1775216715 on cpu 0 ***
PC: @     0x7438eee35b2c  (unknown)  pthread_kill
    @     0x5acb0860da23         64  absl::lts_20250512::WriteFailureInfo()
    @     0x5acb0860dca7         96  absl::lts_20250512::AbslFailureSignalHandler()
    @     0x7438eeddc330       3520  (unknown)
    @     0x7438eeddc27e         32  raise
    @     0x7438eedbf8ff        192  abort
    @     0x5acb085b3bc9        176  google::DumpStackTraceAndExit()
    @     0x5acb085aa79d         16  google::LogMessage::Fail()
    @     0x5acb085aa6e3        160  google::LogMessage::SendToLog()
    @     0x5acb085a9e96         80  google::LogMessage::Flush()
    @     0x5acb085a9c11         48  google::LogMessage::~LogMessage()
    @     0x5acb07f57d0f        640  dfly::DbSlice::AddOrUpdateInternal()
    @     0x5acb07f57eb5        128  dfly::DbSlice::AddOrUpdate()
    @     0x5acb076ee48d        544  dfly::OpStore<>()
    @     0x5acb076e8d3c        176  dfly::SortVisitor::operator()<>()::{lambda()#1}::operator()()
    @     0x5acb076fd3f7         64  std::__invoke_impl<>()
    @     0x5acb076fa538         64  std::__invoke<>()
    @     0x5acb076f69ea         64  std::invoke<>()
    @     0x5acb076f2fd5         96  absl::lts_20250512::functional_internal::InvokeObject<>()
    @     0x5acb0803bc06         64  absl::lts_20250512::FunctionRef<>::operator()()
    @     0x5acb08027a5b        240  dfly::Transaction::RunCallback()
    @     0x5acb08026ecc        384  dfly::Transaction::RunInShard()
    @     0x5acb07ad31cd         80  dfly::EngineShard::PollExecution()::{lambda()#1}::operator()()
    @     0x5acb07ad3a12        416  dfly::EngineShard::PollExecution()
    @     0x5acb0802afe5        448  dfly::Transaction::DispatchHop()
    @     0x5acb0802a34e         64  dfly::Transaction::Execute()
    @     0x5acb076e937b        240  dfly::SortVisitor::operator()<>()

Process exited with code 134 (SIGABRT).
```
