# wasmoon_async

`wasmoon_async` is Wasmoon's single-threaded scheduling core. It owns task
readiness, timer deadlines, cancellable host-operation identities, and stale
event rejection. It deliberately does not own guest tasks, Component Model
values, WASI resources, or a WebAssembly `Store`.

The interface enforces the main ownership seam:

- callers retain task state and poll it only after `next_ready`;
- the runtime stores only task and operation identities;
- a pending operation retains a `Waker`, never mutable guest execution state;
- wakeups are deduplicated;
- task and operation slots carry generations, so late platform events cannot
  target a reused slot;
- task and operation cancellation are idempotent;
- time is monotonic and supplied by the embedding or reactor adapter.

Platform adapters translate kqueue or epoll events into
`Runtime::complete_operation`. Native descriptors remain inside those adapters.

```moonbit check
///|
test "drive one caller-owned task" {
  let runtime = Runtime::Runtime()
  let task = runtime.spawn()
  inspect(runtime.next_ready() == Some(task.id()), content="true")

  guard task.waker().register_timer(10L) is Some(_) else {
    fail("failed to register timer")
  }
  inspect(runtime.advance_to(10L), content="1")
  inspect(runtime.next_ready() == Some(task.id()), content="true")
  task.complete()
}
```
