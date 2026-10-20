///|
test "host and native table writes are immediately visible without a JIT boundary" {
  let store = @runtime.Store::Store()
  defer store.close()
  let table = @runtime.Table::Table(RefNullEq, 1, Some(4), init_value=I31(1))
  let address = store.alloc_table(table)
  let native = store.get_jit_table(address).unwrap()
  table.set(0, I31(7))
  assert_eq(native.get_entry_value(0), 15L)
  native.set(0, 19L, -1)
  assert_eq(table.get(0), I31(9))
  assert_eq(store.alloc_table(table), address)
  table.fill(0, I31(11), 1)
  assert_eq(native.get_entry_value(0), 23L)
}

///|
test "native growth is authoritative for runtime size limits copy and quota" {
  let budget = @runtime.ResourceBudget::new(table_elements=4L)
  let store = @runtime.Store::Store(resource_budget=Some(budget))
  defer store.close()
  let table = @runtime.Table::Table(RefNullEq, 1, Some(4), init_value=I31(1))
  let native = store.get_jit_table(store.alloc_table(table)).unwrap()
  assert_eq(native.raw_ptr().grow_value(2L, 19L, -1), 1L)
  assert_eq(table.size(), 3)
  assert_eq(table.get_limits64(), (3L, Some(4L)))
  assert_eq(table.get(2), I31(9))
  table.copy_from(0, table, 2, 1)
  assert_eq(table.get(0), I31(9))
  assert_eq(table.grow(1, I31(11)), 3)
  assert_eq(native.get_entry_value(3), 23L)
  assert_eq(budget.used(TableElements), 4L)
  assert_eq(table.grow(1, Null), -1)
  table.close()
  assert_eq(native.get_size(), 0)
  assert_eq(native.raw_ptr().grow_value(1L, 0L, -1), -1L)
  store.close()
  assert_eq(budget.used(TableElements), 0L)
}

///|
test "native external tables preserve wrapper identity and root it across collection" {
  let store = @runtime.Store::with_c_heap()
  defer store.close()
  let wrapped = store.wrap_as_extern(I31(7))
  let table = @runtime.Table::Table(ExternRef, 1, None, init_value=wrapped)
  let native = store.get_jit_table(store.alloc_table(table)).unwrap()
  assert_eq(table.get(0), wrapped)
  assert_eq(table.get(0), wrapped)
  store.collect_garbage() |> ignore
  assert_eq(table.get(0), wrapped)
  assert_eq(store.unwrap_extern(table.get(0)), I31(7))
  // A guest write supplies an unwrapped native word. Materialize its host
  // wrapper once, then retain that identity through the authoritative entry.
  native.set(0, 19L, -1)
  let replacement = table.get(0)
  assert_eq(store.unwrap_extern(replacement), I31(9))
  assert_eq(table.get(0), replacement)
  store.collect_garbage() |> ignore
  assert_eq(table.get(0), replacement)
}

///|
extern "c" fn shared_table_live_count() -> Int64 = "wasmoon_jit_debug_shared_indirect_table_live_count"

///|
fn allocate_unretained_table_store() -> Unit raise {
  let store = @runtime.Store::Store()
  store.alloc_table(Table(FuncRef, 1, None)) |> ignore
}

///|
test "native table backing does not retain an otherwise unreferenced Store" {
  let before = shared_table_live_count()
  allocate_unretained_table_store()
  assert_eq(shared_table_live_count(), before)
}

///|
test "late CHeap activation updates tables admitted before and after the switch" {
  for before_activation in [true, false] {
    let store = @runtime.Store::Store()
    defer store.close()
    let table = @runtime.Table::Table(RefNullEq, 2, None)
    if before_activation {
      store.alloc_table(table) |> ignore
    }
    store.enable_c_heap()
    store.enable_c_heap()
    if !before_activation {
      store.alloc_table(table) |> ignore
    }
    let array = store.alloc_array(0, [I32(42)])
    let structure = store.alloc_struct(0, [I32(17)])
    table.set(0, ArrayRef(array))
    table.set(1, StructRef(structure))
    assert_eq(table.get(0), ArrayRef(array))
    assert_eq(table.get(1), StructRef(structure))
    store.close()
    assert_false(store.has_c_heap())
  }
}

///|
test "late CHeap activation traces table roots and reclaims unrelated garbage" {
  let store = @runtime.Store::Store()
  defer store.close()
  let table = @runtime.Table::Table(RefNullEq, 1, None)
  store.alloc_table(table) |> ignore
  store.enable_c_heap()
  let rooted = store.alloc_array(0, [I32(42)])
  table.set(0, ArrayRef(rooted))
  let garbage = store.alloc_array(0, [I32(9)])
  assert_eq(store.collect_garbage(), 1)
  assert_true(store.is_gc_valid(rooted))
  assert_false(store.is_gc_valid(garbage))
  table.set(0, Null)
  assert_eq(store.collect_garbage(), 1)
  assert_false(store.is_gc_valid(rooted))
}

///|
test "late CHeap activation decodes native exception array payloads" {
  let store = @runtime.Store::Store()
  defer store.close()
  store.enable_c_heap()
  let tag = store.alloc_tag({ params: [RefNullEq], results: [], })
  let array = store.alloc_array(0, [I32(42)])
  let arena = store.native_execution_state().exceptions()
  assert_true(arena.define_tag(tag, [RefNullEq]))
  let token = arena.insert(store.get_c_heap_ptr(), tag, [
    (array.to_int64() + 1L) << 1,
  ])
  assert_true(token != 0L)
  guard store.decode_native_exception(token) is ExnRef(exception) else {
    fail("expected native exception")
  }
  assert_eq(store.get_exn(exception).values, [ArrayRef(array)])
  assert_eq(store.encode_native_exception(exception), token)
}

///|
test "null-backed external wrappers retain identity through native tables and GC" {
  let store = @runtime.Store::with_c_heap()
  defer store.close()
  let wrapped = store.wrap_as_extern(Null)
  let initial = @runtime.Table::Table(RefExtern, 1, None, init_value=wrapped)
  store.alloc_table(initial) |> ignore
  assert_eq(initial.get(0), wrapped)
  let mutated = @runtime.Table::Table(ExternRef, 2, None)
  store.alloc_table(mutated) |> ignore
  mutated.set(0, wrapped)
  mutated.copy_from(1, initial, 0, 1)
  assert_eq(mutated.get(0), wrapped)
  assert_eq(mutated.get(1), wrapped)
  assert_eq(store.collect_garbage(), 0)
  assert_eq(store.unwrap_extern(initial.get(0)), Null)
  initial.close()
  mutated.fill(0, Null, 2)
  store.collect_garbage() |> ignore
  try store.unwrap_extern(wrapped) catch {
    UndefinedElement => ()
    error => raise error
  } noraise {
    _ => fail("unrooted wrapper must be released")
  }
}
