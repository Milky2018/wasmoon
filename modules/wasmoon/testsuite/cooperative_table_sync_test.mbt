///|
test "cooperative resumes leave unchanged shared function tables untouched" {
  let source =
    #|(module
    #| (table 1000 funcref)
    #| (func $empty)
    #| (elem (i32.const 0) $empty)
    #| (func (export "run") (param $remaining i32) (result i32)
    #|  (loop $again
    #|   local.get $remaining i32.const 1 i32.sub local.tee $remaining br_if $again)
    #|  local.get $remaining))
  let module_ = @wat.parse(source)
  let store = @runtime.Store::with_c_heap()
  defer store.close()
  let instance = @executor.instantiate_module_with_imports(
    store,
    module_,
    Imports(store),
  )
  let context = prepare_async_jit_context(
    module_,
    instance,
    store,
    cooperative=true,
  )
  defer context.close()
  let table = store.get_jit_table(instance.table_addrs[0]).unwrap().raw_ptr()
  let revision = table.revision()
  let mut outcome = context.call_core_func_resumable(store, instance, 1, [
    I32(10000),
  ])
  defer (if outcome is NativeCoreSuspended(_, continuation) {
    continuation.cancel()
  })
  let mut yields = 0
  while outcome is NativeCoreSuspended(CooperativeYield, continuation) {
    yields += 1
    assert_eq(table.revision(), revision)
    outcome = continuation.continue_execution()
  }
  guard outcome is NativeCoreReturned(values) else {
    fail("unexpected suspension")
  }
  assert_eq(values, [I32(0)])
  assert_true(yields > 1)
  assert_eq(table.revision(), revision)
}

///|
fn cooperative_table_reader() -> @types.Module raise {
  @wat.parse(
    (
      #|(module
      #| (import "shared" "table" (table 4 8 funcref))
      #| (type $result (func (result i32)))
      #| (func $one (type $result) i32.const 1)
      #| (func $two (type $result) i32.const 2)
      #| (elem (i32.const 0) $one $one $one $two)
      #| (func (export "run") (param $remaining i32) (result i32)
      #|  (loop $again
      #|   local.get $remaining i32.const 1 i32.sub local.tee $remaining br_if $again)
      #|  i32.const 0 call_indirect (type $result)))
    ),
  )
}

///|
fn finish_table_reader(
  outcome : @wast.JITCoreCallOutcome,
) -> Array[@types.Value] raise {
  let mut outcome = outcome
  defer (if outcome is NativeCoreSuspended(_, continuation) {
    continuation.cancel()
  })
  while outcome is NativeCoreSuspended(CooperativeYield, continuation) {
    outcome = continuation.continue_execution()
  }
  guard outcome is NativeCoreReturned(values) else {
    fail("unexpected suspension")
  }
  values
}

///|
test "parked JIT observes interpreter set fill copy and growth" {
  for operation in 0..<4 {
    let store = @runtime.Store::with_c_heap()
    defer store.close()
    let table = @runtime.Table::Table(FuncRef, 4, Some(8))
    let table_addr = store.alloc_table(table)
    let imports = @runtime.Imports::Imports(store)
    imports.add_table("shared", "table", table_addr)
    let module_ = cooperative_table_reader()
    let instance = @executor.instantiate_module_with_imports(
      store, module_, imports,
    )
    let context = prepare_async_jit_context(
      module_,
      instance,
      store,
      cooperative=true,
    )
    defer context.close()
    let outcome = context.call_core_func_resumable(store, instance, 2, [
      I32(10000),
    ])
    guard outcome is NativeCoreSuspended(CooperativeYield, continuation) else {
      fail("expected yield")
    }
    defer continuation.cancel()
    let replacement : @types.Value = FuncRef(instance.func_addrs[1])
    match operation {
      0 => table.set(0, replacement)
      1 => table.fill(0, replacement, 1)
      2 => {
        table.set(3, replacement)
        table.copy_from(0, table, 3, 1)
      }
      _ => {
        assert_eq(table.grow(1, replacement), 4)
        table.copy_from(0, table, 4, 1)
      }
    }
    assert_eq(finish_table_reader(outcome), [I32(2)])
  }
}

///|
test "another JIT instance publishes every shared table write to a parked reader" {
  let operations = [
    "i32.const 0 ref.func $two table.set", "i32.const 0 ref.func $two i32.const 4 table.fill",
    "i32.const 3 ref.func $two table.set i32.const 0 i32.const 3 i32.const 1 table.copy",
    "i32.const 0 i32.const 0 i32.const 1 table.init $values", "ref.func $two i32.const 1 table.grow drop i32.const 0 i32.const 4 i32.const 1 table.copy",
  ]
  for operation, instructions in operations {
    let store = @runtime.Store::with_c_heap()
    defer store.close()
    let table = @runtime.Table::Table(FuncRef, 4, Some(8))
    let table_addr = store.alloc_table(table)
    let imports = @runtime.Imports::Imports(store)
    imports.add_table("shared", "table", table_addr)
    let reader = cooperative_table_reader()
    let instance = @executor.instantiate_module_with_imports(
      store, reader, imports,
    )
    let context = prepare_async_jit_context(
      reader,
      instance,
      store,
      cooperative=true,
    )
    defer context.close()
    let writer = @wat.parse(
      "(module (import \"shared\" \"table\" (table 4 8 funcref)) " +
      "(type (func (param i64))) (func $two (result i32) i32.const 2) (elem $values func $two) " +
      "(func (export \"mutate\") " +
      instructions +
      "))",
    )
    let other = @executor.instantiate_module_with_imports(
      store, writer, imports,
    )
    let other_context = prepare_async_jit_context(writer, other, store)
    defer other_context.close()
    let outcome = context.call_core_func_resumable(store, instance, 2, [
      I32(10000),
    ])
    guard outcome is NativeCoreSuspended(CooperativeYield, continuation) else {
      fail("expected yield")
    }
    defer continuation.cancel()
    assert_eq(other_context.call_core_func(store, other, 1, []), [])
    assert_eq(table.get(0), FuncRef(other.func_addrs[0]))
    assert_eq(table.size(), if operation == 4 { 5 } else { 4 })
    assert_eq(finish_table_reader(outcome), [I32(2)])
  }
}

///|
test "native table copyback roots GC references while a call is parked" {
  let source =
    #|(module
    #| (type $value (struct (field i32)))
    #| (table 1 (ref null $value))
    #| (func (export "run") (param $remaining i32) (result i32)
    #|  i32.const 0 i32.const 42 struct.new $value table.set
    #|  (loop $again
    #|   local.get $remaining i32.const 1 i32.sub local.tee $remaining br_if $again)
    #|  i32.const 0 table.get struct.get $value 0))
  let module_ = @wat.parse(source)
  let store = @runtime.Store::with_c_heap()
  defer store.close()
  let instance = @executor.instantiate_module_with_imports(
    store,
    module_,
    Imports(store),
  )
  let context = prepare_async_jit_context(
    module_,
    instance,
    store,
    cooperative=true,
  )
  defer context.close()
  let mut outcome = context.call_core_func_resumable(store, instance, 0, [
    I32(10000),
  ])
  defer (if outcome is NativeCoreSuspended(_, continuation) {
    continuation.cancel()
  })
  let table = store.get_table(instance.table_addrs[0])
  let mut yields = 0
  while outcome is NativeCoreSuspended(CooperativeYield, continuation) {
    yields += 1
    guard table.get(0) is StructRef(_) else {
      fail("native write was not published")
    }
    store.collect_garbage() |> ignore
    outcome = continuation.continue_execution()
  }
  assert_true(yields > 1)
  guard outcome is NativeCoreReturned(values) else {
    fail("unexpected suspension")
  }
  assert_eq(values, [I32(42)])
}

///|
test "native empty bulk operations and failed growth preserve the table revision" {
  let source =
    #|(module
    #| (table 1 1 funcref)
    #| (elem $empty func)
    #| (func (export "run") (result i32)
    #|  i32.const 1 ref.null func i32.const 0 table.fill
    #|  i32.const 1 i32.const 1 i32.const 0 table.copy
    #|  i32.const 1 i32.const 0 i32.const 0 table.init $empty
    #|  ref.null func i32.const 0 table.grow drop
    #|  ref.null func i32.const 1 table.grow))
  let module_ = @wat.parse(source)
  let store = @runtime.Store::with_c_heap()
  defer store.close()
  let instance = @executor.instantiate_module_with_imports(
    store,
    module_,
    Imports(store),
  )
  let context = prepare_async_jit_context(module_, instance, store)
  defer context.close()
  let table = store.get_jit_table(instance.table_addrs[0]).unwrap().raw_ptr()
  let revision = table.revision()
  assert_eq(context.call_core_func(store, instance, 0, []), [I32(-1)])
  assert_eq(table.revision(), revision)
  assert_eq(store.get_table(instance.table_addrs[0]).size(), 1)
}
