# Native async reactor

`Milky2018/wasmoon/async_native` adapts operating-system readiness to opaque
one-shot registrations. It uses kqueue on macOS and epoll, timerfd, and eventfd
on Linux.

`NativeReactor` and `NativeRegistration` are opaque. Platform event structures,
native descriptor ownership, and mutable registration tables are not exposed.
Each registration owns only `Pending`, `Ready`, or `Cancelled` state. The
adapter never retains a WebAssembly Store, component value, host future, or
guest continuation.

The reactor is single-threaded and must be driven on its creation thread.
Cancellation is idempotent and stale events are rejected through monotonic
kernel tokens. Windows is not supported.
