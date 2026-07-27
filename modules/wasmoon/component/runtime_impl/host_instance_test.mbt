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
