///|
test "native host results are admitted before reentering a typed guest" {
  let module_ = @wat.parse(
    (
      #|(module
      #| (type $bytes (array (mut i8)))
      #| (type $words (array (mut i64)))
      #| (type $holder (struct (field i32)))
      #| (import "h" "make" (func $make (result (ref $bytes))))
      #| (func (export "test") (result i32) call $make drop i32.const 42))
    ),
  )
  @validator.validate_module(module_)
  for opt_level in [0, 2, 3] {
    let store = @runtime.Store::with_c_heap()
    defer store.close()
    let result : Ref[@types.Value] = Ref(Null)
    let host = store.alloc_host_func(fn(_) { [result.val] }, func_type={
      params: [],
      results: [RefArray(0)],
    })
    let imports = @runtime.Imports::Imports(store)
    imports.add_func("h", "make", host)
    let instance = @executor.instantiate_module_with_imports(
      store, module_, imports,
    )
    let bytes = store.alloc_array(0, [I32(7)], instance~)
    let words = store.alloc_array(1, [I64(7L)], instance~)
    let struct_ = store.alloc_struct(2, [I32(7)], instance~)
    let fixtures = store.pin_gc_roots([
      ArrayRef(bytes),
      ArrayRef(words),
      StructRef(struct_),
    ])
    defer fixtures.release()
    let context = build_gc_root_context(module_, instance, store, opt_level~)
    defer context.close()
    let completions = Ref(0)
    context.install_hostcall_dispatcher(store, instance, after_dispatch=fn() {
      completions.val += 1
      store.collect_garbage() |> ignore
    })
    result.val = ArrayRef(bytes)
    assert_eq(context.call_core_func(store, instance, 1, []), [I32(42)])
    for
      invalid in [
        @types.Value::Null,
        StructRef(struct_),
        ArrayRef(struct_),
        ArrayRef(words),
        ArrayRef(0x7FFFFFFF),
      ] {
      result.val = invalid
      try context.call_core_func(store, instance, 1, []) catch {
        HostInvocation(TypeMismatch) => ()
        error => fail(error.to_string())
      } noraise {
        _ => fail("invalid host GC result entered typed native code")
      }
    }
    result.val = ArrayRef(bytes)
    assert_eq(context.call_core_func(store, instance, 1, []), [I32(42)])
    assert_eq(completions.val, 7)
  }
}

///|
test "native host results stay rooted across completion-hook collection" {
  let module_ = @wat.parse(
    (
      #|(module (type $a (array (mut i32)))
      #| (import "h" "make" (func $make (result (ref $a))))
      #| (func (export "test") (result i32)
      #|  call $make i32.const 0 array.get $a))
    ),
  )
  let store = @runtime.Store::with_c_heap()
  defer store.close()
  let owner : Ref[@runtime.ModuleInstance?] = Ref(None)
  let host = store.alloc_host_func(
    fn(_) raise @runtime.RuntimeError {
      [ArrayRef(store.alloc_array(0, [I32(42)], instance=owner.val.unwrap()))]
    },
    func_type={ params: [], results: [RefArray(0)], },
  )
  let imports = @runtime.Imports::Imports(store)
  imports.add_func("h", "make", host)
  let instance = @executor.instantiate_module_with_imports(
    store, module_, imports,
  )
  owner.val = Some(instance)
  let context = build_gc_root_context(module_, instance, store, opt_level=2)
  defer context.close()
  context.install_hostcall_dispatcher(store, instance, after_dispatch=fn() {
    store.collect_garbage() |> ignore
  })
  for _ in 0..<3 {
    assert_eq(context.call_core_func(store, instance, 1, []), [I32(42)])
    inspect(store.collect_garbage(), content="1")
  }
}

///|
test "scalar host completions do not consume a GC root lease" {
  let module_ = @wat.parse(
    (
      #|(module
      #| (import "h" "empty" (func $empty))
      #| (import "h" "scalar" (func $scalar (result i32)))
      #| (func (export "test") (result i32) call $empty call $scalar))
    ),
  )
  let budget = @runtime.ResourceBudget::new(pending_work=1L)
  let store = @runtime.Store::with_c_heap(resource_budget=Some(budget))
  defer store.close()
  let imports = @runtime.Imports::Imports(store)
  imports.add_func("h", "empty", store.alloc_host_func(fn(_) { [] }))
  imports.add_func(
    "h",
    "scalar",
    store.alloc_host_func(fn(_) { [I32(42)] }, func_type={
      params: [],
      results: [I32],
    }),
  )
  let instance = @executor.instantiate_module_with_imports(
    store, module_, imports,
  )
  let context = build_gc_root_context(module_, instance, store)
  defer context.close()
  context.install_hostcall_dispatcher(store, instance)
  assert_eq(context.call_core_func(store, instance, 2, []), [I32(42)])
  assert_eq(budget.used(PendingWork), 0L)
}
