///|
test "native storage uses the shared module descriptor and inline arrays" {
  let layout = ContextLayout::new(Module(2, 2, 1)).unwrap()
  let a = NativeJITContext::try_alloc(1, layout=Some(layout)).unwrap()
  let b = NativeJITContext::try_alloc(1, layout=Some(layout)).unwrap()
  inspect(
    @native_test_support.context_layout_shared(a.handle, b.handle),
    content="1",
  )
  let memory = alloc_memory_desc(65536L, Some(2L))
  let table = JITTableOwner::try_alloc(1, None).unwrap()
  defer table.close()
  a.set_memory_pointers([
    MemoryInfo(memory, 65536L, Some(2)),
    MemoryInfo(memory, 65536L, Some(2)),
  ])
  a.set_table_pointers([Some(table.table()), Some(table.table())])
  inspect(@native_test_support.context_storage_bytes(a.handle), content="408")
  a.set_memory_pointers([])
  a.set_table_pointers([])
  let cases : Array[(ContextShape, Int)] = [
    (Module(0, 0, 0), 256),
    (Module(1, 0, 0), 304),
    (Module(0, 1, 0), 328),
    (Module(300, 257, 1), 8912),
  ]
  for (shape, bytes) in cases {
    let context = NativeJITContext::try_alloc(
      0,
      layout=ContextLayout::new(shape),
    ).unwrap()
    assert_eq(@native_test_support.context_storage_bytes(context.handle), bytes)
  }
}
