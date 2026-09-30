# Native WASI and async event-loop integration

The native implementation and its private platform headers ship together in
`Milky2018/wasmoon_jit/host_io/reactor`. It uses kqueue on macOS, epoll/timerfd/
eventfd on Linux, and the interruptible descriptor adapter on Windows.
Registrations are opaque and one-shot. Descriptor registrations own independent
close-on-exec duplicates; monotonic tokens reject stale events after cancellation.
The adapter retains no Wasm Store, component values, or guest continuations.

An embedding that combines native WASI operations with asynchronous HTTP must
call `install_event_loop()` before its first asynchronous operation and before
creating WASI contexts. The Wasmoon CLI performs this initialization for HTTP commands and servers.
The function uses the public `moonbitlang/async.set_external_event_loop` API;
it cannot be installed after async starts, or alongside another independently
installed external loop.

The adapter owns one kernel reactor for the host. Each `NativeReactor` created
while it is installed owns only its own registrations: closing a WASI context
cancels those registrations without closing other contexts' descriptors or the
shared reactor. Without installation, `NativeReactor::try_new()` creates an
independent reactor for synchronous embeddings.

The external loop honors async's zero, finite-millisecond, and indefinite waits.
Native readiness wakes structured HTTP driver tasks; component execution only
polls and advances continuations. Only the external loop consumes kernel events:
context-local zero-timeout polls observe completed registrations, and blocking
waits on shared contexts raise `BlockingWaitInExternalLoop`. This prevents an
inner poll from consuming async's foreign-thread wakeup before its outer loop.
Synchronous invocation APIs use independent reactors without installing the
external loop; they should not be used to drive mixed HTTP workloads.

All registration, cancellation, readiness delivery, and component execution
remain on the MoonBit thread. Async owns its auxiliary I/O waiter. Its callback
calls a C wakeup function directly without touching MoonBit reference counts.
The C callback target holds an owned reference until async joins the waiter;
`terminate` then releases that reference and closes the shared reactor.
Notifications are wakeup hints. Registrations retain their ready state, so
consumers check that state before awaiting another notification.

`testsuite/native_event_loop` verifies native pipe readiness, timer delivery,
async TCP progress, cancellation, context isolation, and normal termination.
`scripts/test_wasi_http.py` additionally runs a real HTTP command guest on both
engines while a long native timer is pending, then cancels that timer after the
HTTP exchange completes. CI runs both on Linux, macOS, and Windows. The native
integration executable also runs under ASan/UBSan through the sanitizer harness.
