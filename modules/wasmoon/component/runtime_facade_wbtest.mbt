///|
fn component_runtime_async_import_fixture() -> Bytes raise @component_text.ComponentTextError {
  @component_text.parse_component_wat(
    (
      #|(component
      #|  (import "host"
      #|    (instance $host
      #|      (export "wait" (func async (result u32)))))
      #|  (alias export $host "wait" (func $wait))
      #|  (export "wait" (func $wait)))
      #|
    ),
  )
}

///|
fn component_runtime_async_host(
  ready : Ref[Bool],
  cancellations : Ref[Int],
) -> ComponentHostInstaller {
  ComponentHostInstaller::from_linker_installer(fn(
    linker,
  ) raise @runtime_impl.ComponentRuntimeError {
    let host_runtime = linker.host_runtime_state()
    let builder = linker.host_instance_builder("host", host_runtime)
    builder.add_async_func(
      "wait",
      { is_async: true, params: [], result: Some(Prim(U32)) },
      fn(_args, _table) {
        HostFuture(
          fn() { if ready.val { Ready([U32(17)]) } else { Pending } },
          fn() { cancellations.val = cancellations.val + 1 },
        )
      },
    )
    linker.add_import("host", Instance(builder.finish()))
  })
}

///|
async test "component async join and runtime close share one call lifecycle" {
  let ready = Ref(false)
  let cancellations = Ref(0)
  let runtime = ComponentRuntime(engine=interpreter_component_engine())
  runtime.install(component_runtime_async_host(ready, cancellations))
  let function = runtime
    .instantiate("async-host", component_runtime_async_import_fixture())
    .bind("wait")
  let joined = function.start([])
  let progress = []
  let result = @async.with_task_group(group => {
    let task = group.spawn(no_wait=true, () => joined.join())
    group.spawn_bg() <| () => {
      progress.push("other process ran")
      ready.val = true
    }
    task.wait()
  })
  ready.val = false
  let cancelled = function.start([])
  debug_inspect(cancelled.poll(), content="Pending")
  runtime.close()
  let cancelled_error = try cancelled.poll() catch {
    error => error
  } noraise {
    _ => fail("expected runtime close to cancel the call")
  }
  inspect(
    (result, progress, cancellations.val, cancelled_error),
    content=(
      #|([U32(17)], [other process ran], 1, Cancelled)
    ),
  )
}
