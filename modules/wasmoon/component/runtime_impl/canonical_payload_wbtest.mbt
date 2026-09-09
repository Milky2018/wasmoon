///|
fn payload_test_resources(
  store : @runtime.Store,
  state : AsyncState,
  table : ResourceTable,
  memory64 : Bool,
  encoding : StringEncoding,
  heap_base? : Int64 = 1024L,
) -> CanonResources raise {
  let pages = (heap_base / 65536L + 1L).to_int()
  let memory = store.alloc_mem(Memory(pages, None, is_memory64=memory64))
  let heap = Ref(heap_base)
  let pointer_type : @types.ValueType = if memory64 { I64 } else { I32 }
  let realloc = alloc_host_core_func(
    store,
    {
      params: [pointer_type, pointer_type, pointer_type, pointer_type],
      results: [pointer_type],
    },
    args => {
      fn integer(value : @types.Value) -> Int64 {
        match value {
          I32(n) => n.to_int64() & 0xffffffffL
          I64(n) => n
          _ => 0
        }
      }
      let old_ptr = integer(args[0])
      let old_size = integer(args[1])
      let alignment = integer(args[2])
      let size = integer(args[3])
      let ptr = (heap.val + alignment - 1L) / alignment * alignment
      heap.val = ptr + size
      let mem = store.get_mem(memory)
      for i = 0L
          i < (if old_size < size { old_size } else { size })
          i = i + 1L {
        mem.store_byte_at(ptr + i, mem.load_byte_at(old_ptr + i))
      }
      if memory64 {
        [I64(ptr)]
      } else {
        [I32(ptr.to_int())]
      }
    },
  )
  {
    mem_addr: Some(memory),
    realloc: Some({
      func: realloc,
      async_state: state,
      owner_component_id: table.id,
    }),
    encoding,
    post_return: None,
  }
}

///|
test "payload transport converts nested values across type environments and memory widths" {
  let store = @runtime.Store::Store()
  defer store.close()
  let state = AsyncState(StreamTable())
  let source = ResourceTable()
  let target = ResourceTable()
  state.resource_tables.set(source.id, source)
  state.resource_tables.set(target.id, target)
  let src_resources = payload_test_resources(store, state, source, false, Utf8)
  let dst_resources = payload_test_resources(store, state, target, true, Utf16)
  let src_types : Array[TypeDef?] = [
    Some(List(Prim(String))),
    Some(
      Record([
        { label: "tag", ty: Prim(U8), },
        { label: "names", ty: TypeIdx(0), },
      ]),
    ),
  ]
  let dst_types : Array[TypeDef?] = [
    Some(DefValType(U64)),
    Some(List(Prim(String))),
    Some(
      Record([
        { label: "tag", ty: Prim(U8), },
        { label: "names", ty: TypeIdx(1), },
      ]),
    ),
  ]
  let source_type : CanonicalPayloadType = {
    ty: Some(TypeIdx(1)),
    types: src_types,
  }
  let target_type : CanonicalPayloadType = {
    ty: Some(TypeIdx(2)),
    types: dst_types,
  }
  let value : ComponentValue = Tuple([
    U8(7),
    List([String("hello"), String("世界")]),
  ])
  store_host_stream_value(
    value,
    TypeIdx(1),
    src_types,
    src_resources,
    store,
    source,
    64,
  )
  let pending = source_type.load(src_resources, store, 64, 1, source)
  pending.store(
    0, 1, source, target_type, dst_resources, store, target, state, 128,
  )
  let output = target_type.load(dst_resources, store, 128, 1, target)
  debug_inspect(
    output.values.map(ComponentValue::to_host_value),
    content="[([U8(7), List([String(\"hello\"), String(\"世界\")])])]",
  )
  let mem = require_memory(dst_resources, store)
  inspect(mem.load_i64(144), content="2")
}

///|
test "memory payloads are independent of the function flat-parameter limit" {
  let store = @runtime.Store::Store()
  defer store.close()
  let table = ResourceTable()
  let state = AsyncState(StreamTable())
  let resources = payload_test_resources(store, state, table, false, Utf8)
  let types : Array[TypeDef?] = [Some(FixedList(Prim(U32), 20))]
  let values : Array[ComponentValue] = []
  for i in 0..<20 {
    values.push(U32(i))
  }
  store_host_stream_value(
    List(values),
    TypeIdx(0),
    types,
    resources,
    store,
    table,
    64,
  )
  let memory = require_memory(resources, store)
  inspect(memory.load_i32(64 + 19 * 4), content="19")
}

///|
test "nested resource results validate handles before returning to the host" {
  let store = @runtime.Store::Store()
  defer store.close()
  let types : Array[TypeDef?] = [
    Some(ResourceType(77, 0x7f, None, GuestDefined)),
    Some(Own(0)),
    Some(Tuple([TypeIdx(1)])),
  ]
  let error = try {
    core_results_to_component(
      [I32(123)],
      { is_async: false, params: [], result: Some(TypeIdx(2)), },
      types,
      { mem_addr: None, realloc: None, post_return: None, encoding: Utf8, },
      store,
      ResourceTable(),
    )
    |> ignore
    "missing error"
  } catch {
    error => error.to_string()
  }
  inspect(error.contains("unknown handle index 123"), content="true")
}

///|
test "asynchronous compound payload snapshots retain high memory64 addresses" {
  let store = @runtime.Store::Store()
  defer store.close()
  let state = AsyncState(StreamTable())
  let source = ResourceTable()
  let target = ResourceTable()
  state.resource_tables.set(source.id, source)
  state.resource_tables.set(target.id, target)
  let src_resources = payload_test_resources(store, state, source, false, Utf8)
  let dst_resources = payload_test_resources(
    store,
    state,
    target,
    true,
    Utf16,
    heap_base=4295032832L,
  )
  let src_types : Array[TypeDef?] = [
    Some(List(Prim(String))),
    Some(
      Record([
        { label: "tag", ty: Prim(U8), },
        { label: "names", ty: TypeIdx(0), },
      ]),
    ),
  ]
  let dst_types : Array[TypeDef?] = [
    Some(DefValType(U64)),
    Some(List(Prim(String))),
    Some(
      Record([
        { label: "tag", ty: Prim(U8), },
        { label: "names", ty: TypeIdx(1), },
      ]),
    ),
  ]
  let source_type : CanonicalPayloadType = {
    ty: Some(TypeIdx(1)),
    types: src_types,
  }
  let target_type : CanonicalPayloadType = {
    ty: Some(TypeIdx(2)),
    types: dst_types,
  }
  let value : ComponentValue = Tuple([
    U8(7),
    List([String("hello"), String("世界")]),
  ])
  store_host_stream_value(
    value,
    TypeIdx(1),
    src_types,
    src_resources,
    store,
    source,
    64,
  )
  let pending = source_type.load(src_resources, store, 64, 1, source)
  pending.store(
    0, 1, source, target_type, dst_resources, store, target, state, 4295065600L,
  )
  let output = target_type.load(dst_resources, store, 4295065600L, 1, target)
  debug_inspect(
    output.values.map(ComponentValue::to_host_value),
    content="[([U8(7), List([String(\"hello\"), String(\"世界\")])])]",
  )
  let mem = require_memory(dst_resources, store)
  inspect(mem.load_i64_at(4295065616L), content="2")
}

///|
test "memory64 string and list bounds reject high bits before narrowing" {
  let store = @runtime.Store::Store()
  defer store.close()
  let memory = store.get_mem(store.alloc_mem(Memory(1, None, is_memory64=true)))
  let types : Array[TypeDef?] = [Some(List(Prim(U32)))]
  let table = ResourceTable()
  for ty in [ValType::Prim(String), TypeIdx(0)] {
    let value = lift_component_value_from_flat(
      ty,
      [I64(0L), I64(0L)],
      types,
      Some(memory),
      true,
      Utf8,
      table,
    )
    inspect(value is String("") || value is List([]), content="true")
    for
      pair in [
        (4294967296L, 0L),
        (0L, 4294967296L),
        (-1L, 0L),
        (0L, -1L),
        (65536L, 1L),
      ] {
      let error = try {
        lift_component_value_from_flat(
          ty,
          [I64(pair.0), I64(pair.1)],
          types,
          Some(memory),
          true,
          Utf8,
          table,
        )
        |> ignore
        "missing error"
      } catch {
        error => error.to_string()
      }
      inspect(error.contains("bounds"), content="true")
    }
  }
}
