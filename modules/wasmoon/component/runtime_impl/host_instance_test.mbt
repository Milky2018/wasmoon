///|
test "host instance builder defines callable typed functions" {
  let linker = @runtime_impl.ComponentLinker()
  let runtime = @runtime_impl.HostRuntimeState()
  let builder = linker.host_instance_builder("test:math", runtime)
  let func_type : @component.FuncType = {
    is_async: false,
    params: [{ label: "value", ty: Prim(U32) }],
    result: Some(Prim(U32)),
  }
  builder.add_func("increment", func_type, fn(
    args : Array[@runtime_impl.ComponentValue],
    _table : @runtime_impl.ResourceTable,
  ) -> Array[@runtime_impl.ComponentValue] raise @runtime_impl.ComponentRuntimeError {
    match args {
      [U32(value)] => [U32(value + 1)]
      _ => raise HostCallError("argument type mismatch")
    }
  })
  let instance = builder.finish()
  debug_inspect(
    instance.call_exported_func("increment", [U32(41)]),
    content="[U32(42)]",
  )
}

///|
test "host interface instances share component runtime state" {
  let linker = @runtime_impl.ComponentLinker()
  let runtime = @runtime_impl.HostRuntimeState()
  let left = linker.host_instance_builder("test:left", runtime).finish()
  let right = linker.host_instance_builder("test:right", runtime).finish()
  debug_inspect(
    (
      left.resource_table.id == right.resource_table.id,
      left.stream_table.next_stream_id == right.stream_table.next_stream_id,
      left.async_state.resource_tables.get(left.resource_table.id) is Some(_),
    ),
    content="(true, true, true)",
  )
}

///|
test "async host functions suspend through the shared event loop" {
  let linker = @runtime_impl.ComponentLinker()
  let runtime = @runtime_impl.HostRuntimeState()
  let ready = Ref(false)
  let waits = Ref(0)
  runtime.set_event_loop(fn() {
    waits.val = waits.val + 1
    ready.val = true
    true
  })
  let builder = linker.host_instance_builder("test:async", runtime)
  builder.add_async_func(
    "wait",
    { is_async: true, params: [], result: Some(Prim(U32)) },
    fn(_args, _table) {
      HostFuture(fn() { if ready.val { Ready([U32(7)]) } else { Pending } }, fn() {
        ()
      })
    },
  )
  let instance = builder.finish()
  debug_inspect(
    (instance.call_exported_func("wait", []), waits.val),
    content="([U32(7)], 1)",
  )
}

///|
test "host runtime keeps its first readiness source" {
  let linker = @runtime_impl.ComponentLinker()
  let runtime = @runtime_impl.HostRuntimeState()
  let first_waits = Ref(0)
  let second_waits = Ref(0)
  runtime.set_event_loop(fn() {
    first_waits.val = first_waits.val + 1
    true
  })
  let install_error = try
    runtime.set_event_loop(fn() {
      second_waits.val = second_waits.val + 1
      true
    })
  catch {
    error => error
  } noraise {
    _ => fail("expected readiness source replacement to be rejected")
  }
  let builder = linker.host_instance_builder("test:readiness-owner", runtime)
  builder.add_async_func(
    "wait",
    { is_async: true, params: [], result: Some(Prim(U32)) },
    fn(_args, _table) {
      HostFuture(
        fn() { if first_waits.val > 0 { Ready([U32(7)]) } else { Pending } },
        fn() { () },
      )
    },
  )
  let result = builder.finish().call_exported_func("wait", [])
  debug_inspect(
    (install_error, result, first_waits.val, second_waits.val),
    content="(HostEventLoopAlreadyInstalled, [U32(7)], 1, 0)",
  )
}

///|
test "component invocations poll and cancel asynchronous host functions" {
  let linker = @runtime_impl.ComponentLinker()
  let runtime = @runtime_impl.HostRuntimeState()
  let ready = Ref(false)
  let cancellations = Ref(0)
  let builder = linker.host_instance_builder("test:async-call", runtime)
  builder.add_async_func(
    "wait",
    { is_async: true, params: [], result: Some(Prim(U32)) },
    fn(_args, _table) {
      HostFuture(fn() { if ready.val { Ready([U32(9)]) } else { Pending } }, fn() {
        cancellations.val = cancellations.val + 1
      })
    },
  )
  let instance = builder.finish()
  let completed = instance.start_exported_func("wait", [])
  debug_inspect(completed.poll(), content="InvocationPending")
  ready.val = true
  debug_inspect(
    (completed.poll(), completed.poll()),
    content="(InvocationReady([U32(9)]), InvocationReady([U32(9)]))",
  )
  ready.val = false
  let cancelled = instance.start_exported_func("wait", [])
  debug_inspect(cancelled.poll(), content="InvocationPending")
  cancelled.cancel()
  cancelled.cancel()
  inspect(cancellations.val, content="1")
  inspect(
    try cancelled.poll() catch {
      error => error
    } noraise {
      _ => fail("expected cancelled invocation")
    },
    content="Cancelled",
  )
}

///|
async test "component invocation join yields to other MoonBit processes" {
  let linker = @runtime_impl.ComponentLinker()
  let runtime = @runtime_impl.HostRuntimeState()
  let ready = Ref(false)
  let progress = []
  let builder = linker.host_instance_builder("test:async-join", runtime)
  builder.add_async_func(
    "wait",
    { is_async: true, params: [], result: Some(Prim(U32)) },
    fn(_args, _table) {
      HostFuture(fn() { if ready.val { Ready([U32(11)]) } else { Pending } }, fn() {
        progress.push("cancelled")
      })
    },
  )
  let invocation = builder.finish().start_exported_func("wait", [])
  let result = @async.with_task_group(group => {
    let joined = group.spawn(no_wait=true, () => invocation.join())
    group.spawn_bg() <| () => {
      progress.push("other process ran")
      ready.val = true
    }
    joined.wait()
  })
  debug_inspect(
    (result, progress),
    content="([U32(11)], [\"other process ran\"])",
  )
}

///|
test "embedding byte streams expose finite data without blocking" {
  let runtime = @runtime_impl.HostRuntimeState()
  let table = runtime.resource_table()
  let stream = runtime.new_host_byte_stream(table, b"abc")
  debug_inspect(
    [
      runtime.read_host_byte_stream(table, stream),
      runtime.read_host_byte_stream(table, stream),
    ],
    content="[Data(<Bytes: [0x61, 0x62, 0x63]>), Closed]",
  )
  runtime.drop_host_readable_stream(table, stream)
}

///|
test "host instance builder rejects duplicate exports" {
  let linker = @runtime_impl.ComponentLinker()
  let builder = linker.host_instance_builder(
    "test:duplicates",
    HostRuntimeState(),
  )
  builder.set_type_space([linker.new_host_resource_type()])
  builder.add_type("resource", 0)
  try builder.add_type("resource", 0) catch {
    e => inspect(e, content="DuplicateHostExport(\"resource\")")
  } noraise {
    _ => fail("expected duplicate host export to be rejected")
  }
}

///|
test "host instance builder rejects invalid function type references" {
  let linker = @runtime_impl.ComponentLinker()
  let builder = linker.host_instance_builder("test:invalid", HostRuntimeState())
  let func_type : @component.FuncType = {
    is_async: false,
    params: [{ label: "value", ty: TypeIdx(0) }],
    result: None,
  }
  try
    builder.add_func("bad", func_type, fn(
      _args : Array[@runtime_impl.ComponentValue],
      _table : @runtime_impl.ResourceTable,
    ) -> Array[@runtime_impl.ComponentValue] raise @runtime_impl.ComponentRuntimeError {
      if _args.length() > 0 {
        raise HostCallError("unexpected arguments")
      }
      []
    })
  catch {
    e => inspect(e, content="InvalidHostTypeReference(0)")
  } noraise {
    _ => fail("expected invalid host type reference to be rejected")
  }
}
