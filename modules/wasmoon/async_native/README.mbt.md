# Native async reactor

`Milky2018/wasmoon/async_native` adapts operating-system readiness to opaque
one-shot registrations. It uses kqueue on macOS and epoll, timerfd, and eventfd
on Linux. On Windows, an event handle supplies wakeups, performance-counter
deadlines supply timers, and the shared descriptor adapter supplies readiness
with bounded polling.

`NativeReactor` and `NativeRegistration` are opaque. Platform event structures,
native descriptor ownership, and mutable registration tables are not exposed.
Each registration owns only `Pending`, `Ready`, or `Cancelled` state. The
adapter never retains a WebAssembly Store, component value, host future, or
guest continuation.

The reactor is single-threaded and must be driven on its creation thread.
Cancellation is idempotent and stale events are rejected through monotonic
registration tokens. Every descriptor registration owns a close-on-exec duplicate,
so concurrent operations for the same descriptor and direction retain
independent readiness and cancellation lifetimes. Windows implementation and
acceptance status are documented in `docs/windows.md`.
