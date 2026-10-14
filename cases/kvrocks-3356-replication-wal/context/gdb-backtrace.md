# GDB Backtrace

Obtained by running `gdb -p <master-pid> --batch -ex 'thread apply all bt'` against the master (`./build/kvrocks`, port 6666) while its connected replica had stopped consuming the replication stream.

## Output

```
0x00007cd44b0b8e51 in ?? () from /lib/x86_64-linux-gnu/libc.so.6

Thread 18 (Thread 0x7cd449bff6c0 (LWP 10) "rocksdb:low"):
#0  0x00007cd44b0b8e51 in ?? () from /lib/x86_64-linux-gnu/libc.so.6
#1  0x00007cd44b0bb8cd in pthread_cond_wait () from /lib/x86_64-linux-gnu/libc.so.6
#2  0x000058dcf9f5144f in rocksdb::ThreadPoolImpl::Impl::BGThread (this=0x7cd44acdd300, thread_id=0) at /workspace/worktrees/kvrocks-3356-replication-wal/build/_deps/rocksdb-src/util/threadpool_imp.cc:236
#3  0x000058dcf9f51a87 in rocksdb::ThreadPoolImpl::Impl::BGThreadWrapper (arg=0x7cd44ac850f0) at /workspace/worktrees/kvrocks-3356-replication-wal/build/_deps/rocksdb-src/util/threadpool_imp.cc:352
#4  0x000058dcf9f59278 in std::__invoke_impl<void, void (*)(void*), rocksdb::BGThreadMetadata*> (__f=@0x7cd44acdc9f0: 0x58dcf9f5195e <rocksdb::ThreadPoolImpl::Impl::BGThreadWrapper(void*)>) at /usr/include/c++/13/bits/invoke.h:61
#5  0x000058dcf9f591fd in std::__invoke<void (*)(void*), rocksdb::BGThreadMetadata*> (__fn=@0x7cd44acdc9f0: 0x58dcf9f5195e <rocksdb::ThreadPoolImpl::Impl::BGThreadWrapper(void*)>) at /usr/include/c++/13/bits/invoke.h:96
#6  0x000058dcf9f5915d in std::thread::_Invoker<std::tuple<void (*)(void*), rocksdb::BGThreadMetadata*> >::_M_invoke<0ul, 1ul> (this=0x7cd44acdc9e8) at /usr/include/c++/13/bits/std_thread.h:292
#7  0x000058dcf9f59112 in std::thread::_Invoker<std::tuple<void (*)(void*), rocksdb::BGThreadMetadata*> >::operator() (this=0x7cd44acdc9e8) at /usr/include/c++/13/bits/std_thread.h:299
#8  0x000058dcf9f590f2 in std::thread::_State_impl<std::thread::_Invoker<std::tuple<void (*)(void*), rocksdb::BGThreadMetadata*> > >::_M_run (this=0x7cd44acdc9e0) at /usr/include/c++/13/bits/std_thread.h:244
#9  0x000058dcfa2fd8d4 in execute_native_thread_routine ()
#10 0x00007cd44b0bcb84 in ?? () from /lib/x86_64-linux-gnu/libc.so.6
#11 0x00007cd44b149cc4 in clone () from /lib/x86_64-linux-gnu/libc.so.6

[... 14 lines omitted ...]

Thread 16 (Thread 0x7cd4487ff6c0 (LWP 12) "rocksdb:high"):
#0  0x00007cd44b0b8e51 in ?? () from /lib/x86_64-linux-gnu/libc.so.6
#1  0x00007cd44b0bb8cd in pthread_cond_wait () from /lib/x86_64-linux-gnu/libc.so.6
#2  0x000058dcf9f5144f in rocksdb::ThreadPoolImpl::Impl::BGThread (this=0x7cd44acdd400, thread_id=0) at /workspace/worktrees/kvrocks-3356-replication-wal/build/_deps/rocksdb-src/util/threadpool_imp.cc:236
#3  0x000058dcf9f51a87 in rocksdb::ThreadPoolImpl::Impl::BGThreadWrapper (arg=0x7cd44ac85130) at /workspace/worktrees/kvrocks-3356-replication-wal/build/_deps/rocksdb-src/util/threadpool_imp.cc:352
#4  0x000058dcf9f59278 in std::__invoke_impl<void, void (*)(void*), rocksdb::BGThreadMetadata*> (__f=@0x7cd44acdc930: 0x58dcf9f5195e <rocksdb::ThreadPoolImpl::Impl::BGThreadWrapper(void*)>) at /usr/include/c++/13/bits/invoke.h:61
#5  0x000058dcf9f591fd in std::__invoke<void (*)(void*), rocksdb::BGThreadMetadata*> (__fn=@0x7cd44acdc930: 0x58dcf9f5195e <rocksdb::ThreadPoolImpl::Impl::BGThreadWrapper(void*)>) at /usr/include/c++/13/bits/invoke.h:96
#6  0x000058dcf9f5915d in std::thread::_Invoker<std::tuple<void (*)(void*), rocksdb::BGThreadMetadata*> >::_M_invoke<0ul, 1ul> (this=0x7cd44acdc928) at /usr/include/c++/13/bits/std_thread.h:292
#7  0x000058dcf9f59112 in std::thread::_Invoker<std::tuple<void (*)(void*), rocksdb::BGThreadMetadata*> >::operator() (this=0x7cd44acdc928) at /usr/include/c++/13/bits/std_thread.h:299
#8  0x000058dcf9f590f2 in std::thread::_State_impl<std::thread::_Invoker<std::tuple<void (*)(void*), rocksdb::BGThreadMetadata*> > >::_M_run (this=0x7cd44acdc920) at /usr/include/c++/13/bits/std_thread.h:244
#9  0x000058dcfa2fd8d4 in execute_native_thread_routine ()
#10 0x00007cd44b0bcb84 in ?? () from /lib/x86_64-linux-gnu/libc.so.6
#11 0x00007cd44b149cc4 in clone () from /lib/x86_64-linux-gnu/libc.so.6

[... 14 lines omitted ...]

Thread 14 (Thread 0x7cd40c9f96c0 (LWP 150) "kvrocks"):
#0  0x00007cd44b0b8e51 in ?? () from /lib/x86_64-linux-gnu/libc.so.6
#1  0x00007cd44b0bbd6e in pthread_cond_timedwait () from /lib/x86_64-linux-gnu/libc.so.6
#2  0x000058dcf9e02ba4 in rocksdb::port::CondVar::TimedWait (this=0x7cd44ac2b690, abs_time_us=1791966643662626) at /workspace/worktrees/kvrocks-3356-replication-wal/build/_deps/rocksdb-src/port/port_posix.cc:133
#3  0x000058dcf9b3397a in rocksdb::InstrumentedCondVar::TimedWaitInternal (this=0x7cd44ac2b690, abs_time_us=1791966643662626) at /workspace/worktrees/kvrocks-3356-replication-wal/build/_deps/rocksdb-src/monitoring/instrumented_mutex.cc:87
#4  0x000058dcf9b338c6 in rocksdb::InstrumentedCondVar::TimedWait (this=0x7cd44ac2b690, abs_time_us=1791966643662626) at /workspace/worktrees/kvrocks-3356-replication-wal/build/_deps/rocksdb-src/monitoring/instrumented_mutex.cc:76
#5  0x000058dcf9984a56 in rocksdb::Timer::Run (this=0x7cd44ac2b640) at /workspace/worktrees/kvrocks-3356-replication-wal/build/_deps/rocksdb-src/util/timer.h:252
#6  0x000058dcf998e325 in std::__invoke_impl<void, void (rocksdb::Timer::*)(), rocksdb::Timer*> (__f=@0x7cd44ad26070: (void (rocksdb::Timer::*)(class rocksdb::Timer * const)) 0x58dcf998474e <rocksdb::Timer::Run()>, __t=@0x7cd44ad26068: 0x7cd44ac2b640) at /usr/include/c++/13/bits/invoke.h:74
#7  0x000058dcf998e279 in std::__invoke<void (rocksdb::Timer::*)(), rocksdb::Timer*> (__fn=@0x7cd44ad26070: (void (rocksdb::Timer::*)(class rocksdb::Timer * const)) 0x58dcf998474e <rocksdb::Timer::Run()>) at /usr/include/c++/13/bits/invoke.h:96
#8  0x000058dcf998e1d9 in std::thread::_Invoker<std::tuple<void (rocksdb::Timer::*)(), rocksdb::Timer*> >::_M_invoke<0ul, 1ul> (this=0x7cd44ad26068) at /usr/include/c++/13/bits/std_thread.h:292
#9  0x000058dcf998e18e in std::thread::_Invoker<std::tuple<void (rocksdb::Timer::*)(), rocksdb::Timer*> >::operator() (this=0x7cd44ad26068) at /usr/include/c++/13/bits/std_thread.h:299
#10 0x000058dcf998e16e in std::thread::_State_impl<std::thread::_Invoker<std::tuple<void (rocksdb::Timer::*)(), rocksdb::Timer*> > >::_M_run (this=0x7cd44ad26060) at /usr/include/c++/13/bits/std_thread.h:244
#11 0x000058dcfa2fd8d4 in execute_native_thread_routine ()
#12 0x00007cd44b0bcb84 in ?? () from /lib/x86_64-linux-gnu/libc.so.6
#13 0x00007cd44b149cc4 in clone () from /lib/x86_64-linux-gnu/libc.so.6

Thread 13 (Thread 0x7cd40d1fa6c0 (LWP 151) "worker"):
#0  0x00007cd44b14a2d2 in epoll_wait () from /lib/x86_64-linux-gnu/libc.so.6
#1  0x000058dcfa0b05ce in epoll_dispatch (base=0x7cd44ad1d400, tv=0x7cd40d1f8d30) at /workspace/worktrees/kvrocks-3356-replication-wal/build/_deps/libevent-src/epoll.c:465
#2  0x000058dcfa09ef6e in event_base_loop (base=0x7cd44ad1d400, flags=0) at /workspace/worktrees/kvrocks-3356-replication-wal/build/_deps/libevent-src/event.c:1992
#3  0x000058dcfa09e922 in event_base_dispatch (event_base=0x7cd44ad1d400) at /workspace/worktrees/kvrocks-3356-replication-wal/build/_deps/libevent-src/event.c:1817
#4  0x000058dcf93996d2 in Worker::Run (this=0x7cd44acdda00, tid=...) at /workspace/worktrees/kvrocks-3356-replication-wal/src/server/worker.cc:317
#5  0x000058dcf939b26b in operator() (__closure=0x7cd445a00070) at /workspace/worktrees/kvrocks-3356-replication-wal/src/server/worker.cc:588
#6  0x000058dcf939c354 in operator() (__closure=0x7cd445a00068) at /workspace/worktrees/kvrocks-3356-replication-wal/src/common/thread_util.h:48
#7  0x000058dcf939e100 in std::__invoke_impl<void, util::CreateThread<WorkerThread::Start()::<lambda()> >(char const*, WorkerThread::Start()::<lambda()>)::<lambda()> >(std::__invoke_other, struct {...} &&) (__f=...) at /usr/include/c++/13/bits/invoke.h:61
#8  0x000058dcf939e0c3 in std::__invoke<util::CreateThread<WorkerThread::Start()::<lambda()> >(char const*, WorkerThread::Start()::<lambda()>)::<lambda()> >(struct {...} &&) (__fn=...) at /usr/include/c++/13/bits/invoke.h:96
#9  0x000058dcf939e070 in std::thread::_Invoker<std::tuple<util::CreateThread<WorkerThread::Start()::<lambda()> >(char const*, WorkerThread::Start()::<lambda()>)::<lambda()> > >::_M_invoke<0>(std::_Index_tuple<0>) (this=0x7cd445a00068) at /usr/include/c++/13/bits/std_thread.h:292
#10 0x000058dcf939e044 in std::thread::_Invoker<std::tuple<util::CreateThread<WorkerThread::Start()::<lambda()> >(char const*, WorkerThread::Start()::<lambda()>)::<lambda()> > >::operator()(void) (this=0x7cd445a00068) at /usr/include/c++/13/bits/std_thread.h:299
#11 0x000058dcf939e028 in std::thread::_State_impl<std::thread::_Invoker<std::tuple<util::CreateThread<WorkerThread::Start()::<lambda()> >(char const*, WorkerThread::Start()::<lambda()>)::<lambda()> > > >::_M_run(void) (this=0x7cd445a00060) at /usr/include/c++/13/bits/std_thread.h:244
#12 0x000058dcfa2fd8d4 in execute_native_thread_routine ()
#13 0x00007cd44b0bcb84 in ?? () from /lib/x86_64-linux-gnu/libc.so.6
#14 0x00007cd44b149cc4 in clone () from /lib/x86_64-linux-gnu/libc.so.6

[... 119 lines omitted ...]

Thread 5 (Thread 0x7cd40f1fe6c0 (LWP 159) "task-runner"):
#0  0x00007cd44b14752d in syscall () from /lib/x86_64-linux-gnu/libc.so.6
#1  0x000058dcf9612282 in tbb::detail::r1::futex_wait (futex=0x7cd40f1fcb88, comparand=2) at build/_deps/tbb-src/src/tbb/semaphore.h:104
#2  0x000058dcf9612be2 in tbb::detail::r1::binary_semaphore::P (this=0x7cd40f1fcb88) at build/_deps/tbb-src/src/tbb/semaphore.h:261
#3  0x000058dcf961454c in tbb::detail::r1::sleep_node<unsigned long>::wait (this=0x7cd40f1fcb60) at build/_deps/tbb-src/src/tbb/concurrent_monitor.h:170
#4  0x000058dcf9613c9f in tbb::detail::r1::concurrent_monitor_base<unsigned long>::commit_wait (this=0x7cd44ac655a8, node=...) at build/_deps/tbb-src/src/tbb/concurrent_monitor.h:232
#5  0x000058dcf96126dc in tbb::detail::r1::concurrent_monitor_base<unsigned long>::wait<tbb::detail::r1::sleep_node<long unsigned int>, tbb::detail::r1::wait_bounded_queue_monitor(concurrent_monitor*, std::size_t, std::ptrdiff_t, tbb::detail::d1::delegate_base&)::<lambda()> >(struct {...} &&, tbb::detail::r1::sleep_node<unsigned long> &&) (this=0x7cd44ac655a8, pred=..., node=...) at build/_deps/tbb-src/src/tbb/concurrent_monitor.h:262
#6  0x000058dcf9612552 in tbb::detail::r1::wait_bounded_queue_monitor (monitors=0x7cd44ac65580, monitor_tag=1, target=6, predicate=...) at build/_deps/tbb-src/src/tbb/concurrent_bounded_queue.cpp:57
#7  0x000058dcf91b0a92 in tbb::detail::d2::concurrent_bounded_queue<std::function<void ()>, tbb::detail::d1::cache_aligned_allocator<std::function<void ()> > >::internal_wait<tbb::detail::d2::concurrent_bounded_queue<std::function<void ()>, tbb::detail::d1::cache_aligned_allocator<std::function<void ()> > >::internal_pop(void*)::{lambda()#1}>(tbb::detail::r1::concurrent_monitor*, unsigned long, long, tbb::detail::d2::concurrent_bounded_queue<std::function<void ()>, tbb::detail::d1::cache_aligned_allocator<std::function<void ()> > >::internal_pop(void*)::{lambda()#1}) (this=0x7ffd96a78f38, monitors=0x7cd44ac65580, monitor_tag=1, target=6, pred=...) at /workspace/worktrees/kvrocks-3356-replication-wal/build/_deps/tbb-src/src/tbb/../../include/oneapi/tbb/concurrent_queue.h:329
#8  0x000058dcf91b02b0 in tbb::detail::d2::concurrent_bounded_queue<std::function<void ()>, tbb::detail::d1::cache_aligned_allocator<std::function<void ()> > >::internal_pop(void*)::{lambda()#2}::operator()() const (__closure=0x7cd40f1fcd20) at /workspace/worktrees/kvrocks-3356-replication-wal/build/_deps/tbb-src/src/tbb/../../include/oneapi/tbb/concurrent_queue.h:621
#9  0x000058dcf91b0bb3 in tbb::detail::d0::try_call_proxy<tbb::detail::d2::concurrent_bounded_queue<std::function<void ()>, tbb::detail::d1::cache_aligned_allocator<std::function<void ()> > >::internal_pop(void*)::{lambda()#2}>::on_exception<tbb::detail::d2::concurrent_bounded_queue<std::function<void ()>, tbb::detail::d1::cache_aligned_allocator<std::function<void ()> > >::internal_pop(void*)::{lambda()#3}>(tbb::detail::d2::concurrent_bounded_queue<std::function<void ()>, tbb::detail::d1::cache_aligned_allocator<std::function<void ()> > >::internal_pop(void*)::{lambda()#3}) (this=0x7cd40f1fcd20, on_exception_body=...) at /workspace/worktrees/kvrocks-3356-replication-wal/build/_deps/tbb-src/src/tbb/../../include/oneapi/tbb/detail/_template_helpers.h:227
#10 0x000058dcf91b04cb in tbb::detail::d2::concurrent_bounded_queue<std::function<void()>, tbb::detail::d1::cache_aligned_allocator<std::function<void()> > >::internal_pop (this=0x7ffd96a78f38, dst=0x7cd40f1fcdb0) at /workspace/worktrees/kvrocks-3356-replication-wal/build/_deps/tbb-src/src/tbb/../../include/oneapi/tbb/concurrent_queue.h:622
#11 0x000058dcf91afe59 in tbb::detail::d2::concurrent_bounded_queue<std::function<void()>, tbb::detail::d1::cache_aligned_allocator<std::function<void()> > >::pop (this=0x7ffd96a78f38, result=...) at /workspace/worktrees/kvrocks-3356-replication-wal/build/_deps/tbb-src/src/tbb/../../include/oneapi/tbb/concurrent_queue.h:499
#12 0x000058dcf91af155 in TaskRunner::run (this=0x7ffd96a78f30) at /workspace/worktrees/kvrocks-3356-replication-wal/src/common/task_runner.cc:64
#13 0x000058dcf91aeb59 in operator() (__closure=0x7cd44acf76f0) at /workspace/worktrees/kvrocks-3356-replication-wal/src/common/task_runner.cc:35
#14 0x000058dcf91af2ca in operator() (__closure=0x7cd44acf76e8) at /workspace/worktrees/kvrocks-3356-replication-wal/src/common/thread_util.h:48
#15 0x000058dcf91af8d6 in std::__invoke_impl<void, util::CreateThread<TaskRunner::Start()::<lambda()> >(char const*, TaskRunner::Start()::<lambda()>)::<lambda()> >(std::__invoke_other, struct {...} &&) (__f=...) at /usr/include/c++/13/bits/invoke.h:61
#16 0x000058dcf91af899 in std::__invoke<util::CreateThread<TaskRunner::Start()::<lambda()> >(char const*, TaskRunner::Start()::<lambda()>)::<lambda()> >(struct {...} &&) (__fn=...) at /usr/include/c++/13/bits/invoke.h:96
#17 0x000058dcf91af846 in std::thread::_Invoker<std::tuple<util::CreateThread<TaskRunner::Start()::<lambda()> >(char const*, TaskRunner::Start()::<lambda()>)::<lambda()> > >::_M_invoke<0>(std::_Index_tuple<0>) (this=0x7cd44acf76e8) at /usr/include/c++/13/bits/std_thread.h:292
#18 0x000058dcf91af81a in std::thread::_Invoker<std::tuple<util::CreateThread<TaskRunner::Start()::<lambda()> >(char const*, TaskRunner::Start()::<lambda()>)::<lambda()> > >::operator()(void) (this=0x7cd44acf76e8) at /usr/include/c++/13/bits/std_thread.h:299
#19 0x000058dcf91af7fe in std::thread::_State_impl<std::thread::_Invoker<std::tuple<util::CreateThread<TaskRunner::Start()::<lambda()> >(char const*, TaskRunner::Start()::<lambda()>)::<lambda()> > > >::_M_run(void) (this=0x7cd44acf76e0) at /usr/include/c++/13/bits/std_thread.h:244
#20 0x000058dcfa2fd8d4 in execute_native_thread_routine ()
#21 0x00007cd44b0bcb84 in ?? () from /lib/x86_64-linux-gnu/libc.so.6
#22 0x00007cd44b149cc4 in clone () from /lib/x86_64-linux-gnu/libc.so.6

Thread 4 (Thread 0x7cd40e9fd6c0 (LWP 160) "server-cron"):
#0  0x00007cd44b10cbdf in clock_nanosleep () from /lib/x86_64-linux-gnu/libc.so.6
#1  0x00007cd44b119b27 in nanosleep () from /lib/x86_64-linux-gnu/libc.so.6
#2  0x000058dcf9355c52 in std::this_thread::sleep_for<long, std::ratio<1l, 1000l> > (__rtime=...) at /usr/include/c++/13/bits/this_thread_sleep.h:80
#3  0x000058dcf933f878 in Server::cron (this=0x7ffd96a78820) at /workspace/worktrees/kvrocks-3356-replication-wal/src/server/server.cc:895
#4  0x000058dcf9338a99 in operator() (__closure=0x7cd44adf3d90) at /workspace/worktrees/kvrocks-3356-replication-wal/src/server/server.cc:208
#5  0x000058dcf934e568 in operator() (__closure=0x7cd44adf3d88) at /workspace/worktrees/kvrocks-3356-replication-wal/src/common/thread_util.h:48
#6  0x000058dcf9352fe6 in std::__invoke_impl<void, util::CreateThread<Server::Start()::<lambda()> >(char const*, Server::Start()::<lambda()>)::<lambda()> >(std::__invoke_other, struct {...} &&) (__f=...) at /usr/include/c++/13/bits/invoke.h:61
#7  0x000058dcf9352f6c in std::__invoke<util::CreateThread<Server::Start()::<lambda()> >(char const*, Server::Start()::<lambda()>)::<lambda()> >(struct {...} &&) (__fn=...) at /usr/include/c++/13/bits/invoke.h:96
#8  0x000058dcf9352ec6 in std::thread::_Invoker<std::tuple<util::CreateThread<Server::Start()::<lambda()> >(char const*, Server::Start()::<lambda()>)::<lambda()> > >::_M_invoke<0>(std::_Index_tuple<0>) (this=0x7cd44adf3d88) at /usr/include/c++/13/bits/std_thread.h:292
#9  0x000058dcf9352e6e in std::thread::_Invoker<std::tuple<util::CreateThread<Server::Start()::<lambda()> >(char const*, Server::Start()::<lambda()>)::<lambda()> > >::operator()(void) (this=0x7cd44adf3d88) at /usr/include/c++/13/bits/std_thread.h:299
#10 0x000058dcf9352e36 in std::thread::_State_impl<std::thread::_Invoker<std::tuple<util::CreateThread<Server::Start()::<lambda()> >(char const*, Server::Start()::<lambda()>)::<lambda()> > > >::_M_run(void) (this=0x7cd44adf3d80) at /usr/include/c++/13/bits/std_thread.h:244
#11 0x000058dcfa2fd8d4 in execute_native_thread_routine ()
#12 0x00007cd44b0bcb84 in ?? () from /lib/x86_64-linux-gnu/libc.so.6
#13 0x00007cd44b149cc4 in clone () from /lib/x86_64-linux-gnu/libc.so.6

Thread 3 (Thread 0x7cd40c1f86c0 (LWP 161) "compact-check"):
#0  0x00007cd44b10cbdf in clock_nanosleep () from /lib/x86_64-linux-gnu/libc.so.6
#1  0x00007cd44b119b27 in nanosleep () from /lib/x86_64-linux-gnu/libc.so.6
#2  0x000058dcf9355c52 in std::this_thread::sleep_for<long, std::ratio<1l, 1000l> > (__rtime=...) at /usr/include/c++/13/bits/this_thread_sleep.h:80
#3  0x000058dcf9338b22 in operator() (__closure=0x7cd44ad2d750) at /workspace/worktrees/kvrocks-3356-replication-wal/src/server/server.cc:210
#4  0x000058dcf934e864 in operator() (__closure=0x7cd44ad2d748) at /workspace/worktrees/kvrocks-3356-replication-wal/src/common/thread_util.h:48
#5  0x000058dcf9352fa9 in std::__invoke_impl<void, util::CreateThread<Server::Start()::<lambda()> >(char const*, Server::Start()::<lambda()>)::<lambda()> >(std::__invoke_other, struct {...} &&) (__f=...) at /usr/include/c++/13/bits/invoke.h:61
#6  0x000058dcf9352f19 in std::__invoke<util::CreateThread<Server::Start()::<lambda()> >(char const*, Server::Start()::<lambda()>)::<lambda()> >(struct {...} &&) (__fn=...) at /usr/include/c++/13/bits/invoke.h:96
#7  0x000058dcf9352e9a in std::thread::_Invoker<std::tuple<util::CreateThread<Server::Start()::<lambda()> >(char const*, Server::Start()::<lambda()>)::<lambda()> > >::_M_invoke<0>(std::_Index_tuple<0>) (this=0x7cd44ad2d748) at /usr/include/c++/13/bits/std_thread.h:292
#8  0x000058dcf9352e52 in std::thread::_Invoker<std::tuple<util::CreateThread<Server::Start()::<lambda()> >(char const*, Server::Start()::<lambda()>)::<lambda()> > >::operator()(void) (this=0x7cd44ad2d748) at /usr/include/c++/13/bits/std_thread.h:299
#9  0x000058dcf9352e12 in std::thread::_State_impl<std::thread::_Invoker<std::tuple<util::CreateThread<Server::Start()::<lambda()> >(char const*, Server::Start()::<lambda()>)::<lambda()> > > >::_M_run(void) (this=0x7cd44ad2d740) at /usr/include/c++/13/bits/std_thread.h:244
#10 0x000058dcfa2fd8d4 in execute_native_thread_routine ()
#11 0x00007cd44b0bcb84 in ?? () from /lib/x86_64-linux-gnu/libc.so.6
#12 0x00007cd44b149cc4 in clone () from /lib/x86_64-linux-gnu/libc.so.6

Thread 2 (Thread 0x7cd40b3ff6c0 (LWP 317) "feed-replica"):
#0  0x00007cd44b13c87d in write () from /lib/x86_64-linux-gnu/libc.so.6
#1  0x000058dcf91a2b8f in util::WriteImpl<&write, int> (fd=49, data=...) at /workspace/worktrees/kvrocks-3356-replication-wal/src/common/io_util.cc:441
#2  0x000058dcf91a1aa3 in util::Write (fd=49, data=...) at /workspace/worktrees/kvrocks-3356-replication-wal/src/common/io_util.cc:450
#3  0x000058dcf91a0c2a in util::SockSend (fd=49, data=...) at /workspace/worktrees/kvrocks-3356-replication-wal/src/common/io_util.cc:204
#4  0x000058dcf91a1bbe in util::SockSend (fd=49, data=..., bev=0x7cd40b400000) at /workspace/worktrees/kvrocks-3356-replication-wal/src/common/io_util.cc:467
#5  0x000058dcf8e792a7 in FeedSlaveThread::loop (this=0x7cd40b422000) at /workspace/worktrees/kvrocks-3356-replication-wal/src/cluster/replication.cc:225
#6  0x000058dcf8e77e77 in operator() (__closure=0x7cd40b418010) at /workspace/worktrees/kvrocks-3356-replication-wal/src/cluster/replication.cc:82
#7  0x000058dcf8e83f50 in operator() (__closure=0x7cd40b418008) at /workspace/worktrees/kvrocks-3356-replication-wal/src/common/thread_util.h:48
#8  0x000058dcf8e893e1 in std::__invoke_impl<void, util::CreateThread<FeedSlaveThread::Start()::<lambda()> >(char const*, FeedSlaveThread::Start()::<lambda()>)::<lambda()> >(std::__invoke_other, struct {...} &&) (__f=...) at /usr/include/c++/13/bits/invoke.h:61
#9  0x000058dcf8e892ca in std::__invoke<util::CreateThread<FeedSlaveThread::Start()::<lambda()> >(char const*, FeedSlaveThread::Start()::<lambda()>)::<lambda()> >(struct {...} &&) (__fn=...) at /usr/include/c++/13/bits/invoke.h:96
#10 0x000058dcf8e8915e in std::thread::_Invoker<std::tuple<util::CreateThread<FeedSlaveThread::Start()::<lambda()> >(char const*, FeedSlaveThread::Start()::<lambda()>)::<lambda()> > >::_M_invoke<0>(std::_Index_tuple<0>) (this=0x7cd40b418008) at /usr/include/c++/13/bits/std_thread.h:292
#11 0x000058dcf8e89086 in std::thread::_Invoker<std::tuple<util::CreateThread<FeedSlaveThread::Start()::<lambda()> >(char const*, FeedSlaveThread::Start()::<lambda()>)::<lambda()> > >::operator()(void) (this=0x7cd40b418008) at /usr/include/c++/13/bits/std_thread.h:299
#12 0x000058dcf8e88e7e in std::thread::_State_impl<std::thread::_Invoker<std::tuple<util::CreateThread<FeedSlaveThread::Start()::<lambda()> >(char const*, FeedSlaveThread::Start()::<lambda()>)::<lambda()> > > >::_M_run(void) (this=0x7cd40b418000) at /usr/include/c++/13/bits/std_thread.h:244
#13 0x000058dcfa2fd8d4 in execute_native_thread_routine ()
#14 0x00007cd44b0bcb84 in ?? () from /lib/x86_64-linux-gnu/libc.so.6
#15 0x00007cd44b149cc4 in clone () from /lib/x86_64-linux-gnu/libc.so.6

Thread 1 (Thread 0x7cd44b01d680 (LWP 8) "kvrocks"):
#0  0x00007cd44b0b8e51 in ?? () from /lib/x86_64-linux-gnu/libc.so.6
#1  0x00007cd44b0be883 in ?? () from /lib/x86_64-linux-gnu/libc.so.6
#2  0x000058dcfa2fd94f in std::thread::join() ()
#3  0x000058dcf91b1ce6 in util::ThreadOperationImpl<&std::thread::join> (t=..., op=0x58dcfa3392de "join") at /workspace/worktrees/kvrocks-3356-replication-wal/src/common/thread_util.cc:39
#4  0x000058dcf91b1c19 in util::ThreadJoin (t=...) at /workspace/worktrees/kvrocks-3356-replication-wal/src/common/thread_util.cc:47
#5  0x000058dcf9339cfd in Server::Join (this=0x7ffd96a78820) at /workspace/worktrees/kvrocks-3356-replication-wal/src/server/server.cc:265
#6  0x000058dcf8e0654c in main (argc=3, argv=0x7ffd96a79a18) at /workspace/worktrees/kvrocks-3356-replication-wal/src/cli/main.cc:210
[Inferior 1 (process 8) detached]
```
