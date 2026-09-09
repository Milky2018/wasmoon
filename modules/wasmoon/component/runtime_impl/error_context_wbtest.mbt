///|
test "error-context ABI is a memory-independent i32 handle on both memory widths" {
  for memory64 in [false, true] {
    let plan = @component.canonical_abi_plan(Prim(ErrorContext), [], memory64).unwrap()
    debug_inspect(plan.flat, content="[I32]")
    debug_inspect(plan.layout, content="Some((4, 4))")
    inspect(plan.contains_memory, content="false")
    let store = @runtime.Store::Store()
    defer store.close()
    let memory = store.get_mem(
      store.alloc_mem(Memory(1, None, is_memory64=memory64)),
    )
    memory.store_i32(4, 0x12345678)
    store_flat_component_value_to_memory(
      memory,
      0,
      Prim(ErrorContext),
      [I32(7)],
      [],
      memory64,
    )
    inspect(memory.load_i32(4), content="305419896")
    debug_inspect(
      load_flat_component_value_from_memory(
        memory,
        0,
        Prim(ErrorContext),
        [],
        memory64,
      ),
      content="[I32(7)]",
    )
  }
}

///|
test "error-context payload snapshots survive source drops and use the destination table" {
  let store = @runtime.Store::Store()
  defer store.close()
  let state = AsyncState(StreamTable())
  let source = ResourceTable()
  let target = ResourceTable()
  state.resource_tables.set(source.id, source)
  state.resource_tables.set(target.id, target)
  let src = payload_test_resources(store, state, source, false, Utf8)
  let dst = payload_test_resources(store, state, target, true, Utf16)
  let payload_type : CanonicalPayloadType = {
    ty: Some(TypeIdx(0)),
    types: [Some(Tuple([Prim(U8), Prim(ErrorContext), Prim(U32)]))],
  }
  let input = Tuple([U8(7), ErrorContext("hello"), U32(99)])
  store_host_stream_value(
    input,
    TypeIdx(0),
    payload_type.types,
    src,
    store,
    source,
    64,
  )
  let pending = payload_type.load(src, store, 64, 1, source)
  let handle = require_memory(src, store).load_i32(68)
  inspect(source.drop_error_context(handle), content="true")
  let other = target.alloc_error_context("other")
  pending.store(0, 1, source, payload_type, dst, store, target, state, 128)
  let output = payload_type.load(dst, store, 128, 1, target)
  inspect(output.values == [input], content="true")
  debug_inspect(target.error_contexts.get(other), content="Some(\"other\")")
  inspect(require_memory(dst, store).load_i32(136), content="99")
}

///|
test "lowering a wrong resource type preserves the caller handle" {
  let store = @runtime.Store::Store()
  defer store.close()
  let source = ResourceTable()
  let target = ResourceTable()
  let handle = source.alloc({
    type_id: 1,
    rep: 42,
    dtor: None,
    host_dtor: None,
    kind: GuestDefined,
    impl_component_id: source.id,
    own: true,
    borrow_scope: None,
    num_lends: [0],
  })
  let error = try {
    lower_component_value_to_flat(
      U32(handle),
      TypeIdx(1),
      [Some(ResourceType(2, 0x7f, None, GuestDefined)), Some(Own(0))],
      { mem_addr: None, realloc: None, post_return: None, encoding: Utf8, },
      store,
      (source, target),
    )
    |> ignore
    "missing error"
  } catch {
    error => error.to_string()
  }
  inspect(error.contains("wrong type"), content="true")
  inspect(source.get(handle) is Some(_), content="true")
  inspect(target.entries.val.length(), content="0")
}
