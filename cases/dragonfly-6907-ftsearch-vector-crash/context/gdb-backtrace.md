# GDB Backtrace

## How this was obtained

Ran Dragonfly under GDB (`gdb --args ./build-dbg/dragonfly --port 6379 --logtostderr --proactor_threads 1 --dbfilename=""`), reproduced the crash by creating a VECTOR index with DIM=4, inserting a document with only 8 bytes of vector data (2 floats instead of the expected 4), and executing `FT.SEARCH idx '*'`. GDB caught the signal and `thread apply all bt` was run.

## Evidence

```
Thread 3 "shard-0" received signal SIGSEGV, Segmentation fault.
[Switching to Thread 0x7f3a8c0e1700 (LWP 91302)]
0x00000000034a7c12 in absl::Span<float const>::operator[] (this=0x7f3a8c0deb40, i=2)
    at /src/helio/third_party/abseil-cpp/absl/types/span.h:284

(gdb) bt
#0  0x00000000034a7c12 in absl::Span<float const>::operator[] (this=0x7f3a8c0deb40, i=2)
    at /src/helio/third_party/abseil-cpp/absl/types/span.h:284
#1  0x00000000034a6e45 in dfly::search::(anonymous namespace)::SerializeField (this=0x7f3a8c0dec10,
    field_info=..., value=...) at /src/src/server/search/doc_accessors.cc:60
#2  0x00000000034c1a82 in dfly::search::ShardDocIndex::SearchResultToReply (this=0x61400000f280,
    params=..., result=..., db_cntx=...) at /src/src/server/search/doc_index.cc:218
#3  0x00000000034b8f10 in dfly::SearchFamily::FtSearch (args=..., cntx=0x61d00001f100)
    at /src/src/server/search/search_family.cc:312
#4  0x0000000002a3fb20 in dfly::facade::Connection::DispatchOperations::operator() (
    this=0x7f3a8c0df140, msg=...) at /src/src/server/common/connection.cc:482
#5  0x0000000002a42318 in dfly::facade::Connection::IoLoop (this=0x60d00001c300,
    peer=0x60d00001c400) at /src/src/server/common/connection.cc:614
#6  0x000000000210b9d2 in util::FiberPool::WorkerFunc () at /src/helio/util/fiber_pool.cc:98
#7  0x0000000001f8d240 in boost::context::detail::fiber_entry<...> ()
    at /src/helio/third_party/boost/libs/context/include/boost/context/fiber_fcontext.hpp:79

(gdb) thread apply all bt

Thread 5 "shard-1" (Thread 0x7f3a8b8e0700 (LWP 91303)):
#0  0x00007f3a9e2a4d61 in __GI___ioctl () at ../sysdeps/unix/sysv/linux/ioctl.c:36
#1  0x000000000213fc44 in util::uring::UringProactor::EpollWait (this=0x6120000000c0, timeout=...)
    at /src/helio/util/uring/proactor.cc:502
#2  0x0000000002140b18 in util::uring::UringProactor::MainLoop (this=0x6120000000c0)
    at /src/helio/util/uring/proactor.cc:388
#3  0x000000000210e820 in util::ProactorPool::RunThread (this=0x613000000040, index=1)
    at /src/helio/util/proactor_pool.cc:182
#4  0x00007f3a9e1a6609 in start_thread (arg=<optimized out>) at pthread_create.c:477
#5  0x00007f3a9e0c7133 in clone () at ../sysdeps/unix/sysv/linux/x86_64/clone.S:95

Thread 4 "accept" (Thread 0x7f3a8c8e2700 (LWP 91301)):
#0  0x00007f3a9e2a4d61 in __GI___ioctl () at ../sysdeps/unix/sysv/linux/ioctl.c:36
#1  0x000000000213fc44 in util::uring::UringProactor::EpollWait (this=0x6120000001c0, timeout=...)
    at /src/helio/util/uring/proactor.cc:502
#2  0x0000000002140b18 in util::uring::UringProactor::MainLoop (this=0x6120000001c0)
    at /src/helio/util/uring/proactor.cc:388
#3  0x000000000210e820 in util::ProactorPool::RunThread (this=0x613000000040, index=0)
    at /src/helio/util/proactor_pool.cc:182
#4  0x00007f3a9e1a6609 in start_thread (arg=<optimized out>) at pthread_create.c:477
#5  0x00007f3a9e0c7133 in clone () at ../sysdeps/unix/sysv/linux/x86_64/clone.S:95

Thread 2 "main" (Thread 0x7f3a8d0e3700 (LWP 91300)):
#0  0x00007f3a9e2a4d61 in __GI___ioctl () at ../sysdeps/unix/sysv/linux/ioctl.c:36
#1  0x000000000213fc44 in util::uring::UringProactor::EpollWait (this=0x6120000002c0, timeout=...)
    at /src/helio/util/uring/proactor.cc:502
#2  0x0000000002140b18 in util::uring::UringProactor::MainLoop (this=0x6120000002c0)
    at /src/helio/util/uring/proactor.cc:388
#3  0x000000000210e820 in util::ProactorPool::RunThread (this=0x613000000040, index=2)
    at /src/helio/util/proactor_pool.cc:182
#4  0x00007f3a9e1a6609 in start_thread (arg=<optimized out>) at pthread_create.c:477
#5  0x00007f3a9e0c7133 in clone () at ../sysdeps/unix/sysv/linux/x86_64/clone.S:95

Thread 1 "dragonfly" (Thread 0x7f3a9e1de740 (LWP 91247)):
#0  0x00007f3a9e0c0d2e in epoll_wait (epfd=3, events=0x7ffd4a2c7c10, maxevents=128,
    timeout=1000) at ../sysdeps/unix/sysv/linux/epoll_wait.c:30
#1  0x000000000213fef0 in util::uring::UringProactor::EpollWait (this=0x6120000003c0, timeout=...)
    at /src/helio/util/uring/proactor.cc:510
#2  0x0000000002140b18 in util::uring::UringProactor::MainLoop (this=0x6120000003c0)
    at /src/helio/util/uring/proactor.cc:388
#3  0x0000000001e82400 in dfly::RunEngine(util::ProactorPool*, dfly::HttpListener<>*) ()
    at /src/src/server/main.cc:412

(gdb) print i
$1 = 2
(gdb) print this->size_
$2 = 2
```
