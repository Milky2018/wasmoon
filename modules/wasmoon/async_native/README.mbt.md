# Native async reactor

`Milky2018/wasmoon/async_native` adapts operating-system readiness to the
identity-only `Milky2018/wasmoon_async` scheduler. It uses kqueue on macOS and
epoll, timerfd, and eventfd on Linux.

`NativeReactor` and `NativeRegistration` are opaque. Platform event structures,
native descriptor ownership, and mutable registration tables are not exposed.
The adapter retains a `Waker`, never a WebAssembly Store, component value, host
future, or guest continuation.

The reactor is single-threaded and must be driven on its creation thread.
Cancellation is idempotent and stale events are rejected through scheduler
operation generations. Windows is not supported.
