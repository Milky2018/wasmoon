///|
fn native_gc_allocation_module() -> @types.Module raise {
  let source =
    #|(module
    #|  (type $s (struct (field i32)))
    #|  (type $a (array i32))
    #|  (type $v (struct (field v128)))
    #|  (type $av (array v128))
    #|  (func (export "struct") (result i32)
    #|    (struct.get $s 0 (struct.new $s (i32.const 42))))
    #|  (func (export "array") (result i32)
    #|    (array.get $a (array.new $a (i32.const 42) (i32.const 2)) (i32.const 1)))
    #|  (func (export "fixed") (result i32)
    #|    (array.get $a (array.new_fixed $a 2 (i32.const 41) (i32.const 42)) (i32.const 1)))
    #|  (func (export "wide-struct") (result i32)
    #|    (i32x4.extract_lane 3 (struct.get $v 0 (struct.new $v (v128.const i32x4 1 2 3 42)))))
    #|  (func (export "wide-array") (result i32)
    #|    (i32x4.extract_lane 3 (array.get $av
    #|      (array.new $av (v128.const i32x4 1 2 3 42) (i32.const 2)) (i32.const 1))))
    #|  (func (export "wide-fixed") (result i32)
    #|    (i32x4.extract_lane 3 (array.get $av
    #|      (array.new_fixed $av 2 (v128.const i32x4 1 2 3 41)
    #|        (v128.const i32x4 1 2 3 42)) (i32.const 1)))))
  @wat.parse(source)
}

///|
test "all native allocation layouts retry and preserve payloads" {
  let module_ = native_gc_allocation_module()
  @validator.validate_module(module_)
  // A budget makes scalar allocations enter the allocator instead of writing
  // an inline object; fault injection then exercises its collection retry.
  let budget = @runtime.ResourceBudget::new(gc_bytes=4096L, gc_objects=64L)
  let store = @runtime.Store::with_c_heap(resource_budget=Some(budget))
  defer store.close()
  let instance = @executor.instantiate_module_with_imports(
    store,
    module_,
    Imports(store),
  )
  let context = build_gc_root_context(module_, instance, store)
  defer context.close()
  defer @wasmoon_jit.gc_debug_set_fail_alloc(0)
  for index in 0..<6 {
    @wasmoon_jit.gc_debug_set_fail_alloc(1)
    assert_eq(context.call_core_func(store, instance, index, []), [I32(42)])
    @wasmoon_jit.gc_debug_set_fail_alloc(0, fail_every=1)
    try context.call_core_func(store, instance, index, []) catch {
      Trap(message) => assert_eq(message, "out of memory")
      error => fail(error.to_string())
    } noraise {
      _ => fail("persistent allocation failure was ignored")
    }
    @wasmoon_jit.gc_debug_set_fail_alloc(0)
    assert_eq(context.call_core_func(store, instance, index, []), [I32(42)])
  }
  store.collect_garbage() |> ignore
  assert_eq(budget.used(GcBytes), 0L)
}

///|
test "allocation root visitor failure stays distinct from exhaustion and aborts before reuse" {
  let module_ = native_gc_allocation_module()
  let store = @runtime.Store::with_c_heap(
    resource_budget=Some(@runtime.ResourceBudget::new(gc_bytes=4096L)),
  )
  defer store.close()
  let instance = @executor.instantiate_module_with_imports(
    store,
    module_,
    Imports(store),
  )
  let context = build_gc_root_context(module_, instance, store)
  defer context.close()
  let heap = store.native_heap().unwrap()
  defer @wasmoon_jit.gc_debug_set_fail_alloc(0)
  for index in 0..<6 {
    let aborted = Ref(0)
    store.begin_gc_tracing()
    heap.bind_root_visitor(fn(phase, _) {
      if phase == 2 {
        aborted.val += 1
      }
      if phase == 0 {
        [-2L]
      } else {
        []
      }
    })
    @wasmoon_jit.gc_debug_set_fail_alloc(1)
    try context.call_core_func(store, instance, index, []) catch {
      Trap(message) => assert_eq(message, "gc precise roots unavailable")
      error => fail(error.to_string())
    } noraise {
      _ => fail("allocation continued after its root visitor failed")
    }
    store.end_gc_tracing()
    assert_eq(aborted.val, 1)
    @wasmoon_jit.gc_debug_set_fail_alloc(0)
    assert_eq(context.call_core_func(store, instance, index, []), [I32(42)])
  }
}

///|
test "all native allocation layouts retain byte and identity quota classifications" {
  let module_ = native_gc_allocation_module()
  for byte_limit in [false, true] {
    let budget = if byte_limit {
      @runtime.ResourceBudget::new(gc_bytes=0L)
    } else {
      @runtime.ResourceBudget::new(gc_objects=0L)
    }
    let store = @runtime.Store::with_c_heap(resource_budget=Some(budget))
    defer store.close()
    let instance = @executor.instantiate_module_with_imports(
      store,
      module_,
      Imports(store),
    )
    let context = build_gc_root_context(module_, instance, store)
    defer context.close()
    for index in 0..<6 {
      try context.call_core_func(store, instance, index, []) catch {
        HostInvocation(ResourceLimitExceeded(kind)) =>
          assert_eq(kind, if byte_limit { GcBytes } else { GcObjects })
        error => fail(error.to_string())
      } noraise {
        _ => fail("allocation escaped its quota")
      }
      assert_eq(budget.used(GcBytes), 0L)
      assert_eq(budget.used(GcObjects), 0L)
    }
  }
}

///|
test "allocation retry keeps references staged in scalar and mixed vector payloads" {
  let source =
    #|(module
    #|  (type $leaf (struct (field i32)))
    #|  (type $scalar (struct (field (ref $leaf))))
    #|  (type $mixed (struct (field v128) (field (ref $leaf))))
    #|  (type $array (array (ref $leaf)))
    #|  (func (export "scalar") (result i32)
    #|    (struct.get $leaf 0 (struct.get $scalar 0
    #|      (struct.new $scalar (struct.new $leaf (i32.const 42))))))
    #|  (func (export "mixed") (result i32)
    #|    (struct.get $leaf 0 (struct.get $mixed 1
    #|      (struct.new $mixed (v128.const i64x2 -1 -2) (struct.new $leaf (i32.const 42))))))
    #|  (func (export "array") (result i32)
    #|    (struct.get $leaf 0 (array.get $array
    #|      (array.new $array (struct.new $leaf (i32.const 42)) (i32.const 2)) (i32.const 1))))
    #|  (func (export "fixed") (result i32)
    #|    (struct.get $leaf 0 (array.get $array
    #|      (array.new_fixed $array 1 (struct.new $leaf (i32.const 42))) (i32.const 0)))))
  let module_ = @wat.parse(source)
  @validator.validate_module(module_)
  let store = @runtime.Store::with_c_heap(
    resource_budget=Some(@runtime.ResourceBudget::new(gc_bytes=4096L)),
  )
  defer store.close()
  let instance = @executor.instantiate_module_with_imports(
    store,
    module_,
    Imports(store),
  )
  let context = build_gc_root_context(module_, instance, store)
  defer context.close()
  defer @wasmoon_jit.gc_debug_set_fail_alloc(0)
  for index in 0..<4 {
    // The child exists only in the payload being staged for its parent.
    @wasmoon_jit.gc_debug_set_fail_alloc(2)
    assert_eq(context.call_core_func(store, instance, index, []), [I32(42)])
  }
}

///|
#borrow(heap)
extern "c" fn set_allocation_budget(
  heap : @wasmoon_jit.GCHeapHandle,
  bytes : Int64,
) -> Unit = "wasmoon_test_gc_allocation_budget"

///|
test "native allocation pressure collects before physical exhaustion and keeps caller roots" {
  let module_ = @wat.parse(
    (
      #|(module (type $s (struct (field i32)))
      #| (func $garbage (local $n i32)
      #|   (loop $l (drop (struct.new $s (i32.const 1)))
      #|     (br_if $l (i32.lt_u (local.tee $n (i32.add (local.get $n) (i32.const 1))) (i32.const 100)))))
      #| (func (export "run") (result i32) (local $live (ref $s))
      #|   (local.set $live (struct.new $s (i32.const 42)))
      #|   call $garbage (struct.get $s 0 (local.get $live))))
    ),
  )
  let store = @runtime.Store::with_c_heap()
  defer store.close()
  let instance = @executor.instantiate_module_with_imports(
    store,
    module_,
    Imports(store),
  )
  let context = build_gc_root_context(module_, instance, store)
  defer context.close()
  let heap = store.native_heap().unwrap()
  set_allocation_budget(heap.get_ptr(), 512L)
  assert_eq(context.call_core_func(store, instance, 1, []), [I32(42)])
  assert_true(heap.get_total_collections() > 0)
  store.collect_garbage() |> ignore
}

///|
test "typed native heap packs mixed fields and arrays without changing values or roots" {
  let module_ = @wat.parse(
    (
      #|(module
      #| (type $leaf (struct (field i32)))
      #| (type $mixed (struct (field (mut i8)) (field i16) (field i32) (field f32)
      #|   (field i64) (field f64) (field v128) (field (ref null $leaf))))
      #| (type $bytes (array (mut i8))))
    ),
  )
  let store = @runtime.Store::with_c_heap()
  defer store.close()
  store.set_module_types(module_.types, rec_groups=module_.type_rec_groups)
  let heap = store.native_heap().unwrap()
  let leaf = store.alloc_struct(0, [I32(42)])
  let vector : @types.Value = V128(Bytes::make(16, b'\xa5'))
  let mixed = store.alloc_struct(1, [
    I32(255),
    I32(65534),
    I32(-42),
    F32(1.5),
    I64(-7L),
    F64(2.5),
    vector,
    StructRef(leaf),
  ])
  let bytes = store.alloc_array_repeated(2, 64, I32(255))
  // 32-byte leaf, 80-byte mixed object, 32-byte array prefix + 64 bytes.
  assert_eq(heap.get_size(), 208L)
  let expected : Array[@types.Value] = [
    I32(255),
    I32(65534),
    I32(-42),
    F32(1.5),
    I64(-7L),
    F64(2.5),
    vector,
    StructRef(leaf),
  ]
  for field, value in expected {
    assert_eq(store.struct_get(mixed, field), value)
  }
  store.struct_set(mixed, 0, I32(7))
  assert_eq(store.struct_get(mixed, 0), I32(7))
  store.array_fill(bytes, 0, I32(42), 4)
  store.array_copy(bytes, 2, bytes, 0, 4)
  assert_eq(store.array_get(bytes, 5), I32(42))
  store.collect_garbage(additional_roots=[StructRef(mixed), ArrayRef(bytes)])
  |> ignore
  assert_eq(store.struct_get(leaf, 0), I32(42))
  assert_eq(store.struct_get(mixed, 6), vector)
  assert_eq(store.array_get(bytes, 63), I32(255))
}

///|
test "typed graph tracing preserves cycles signed i31 and public transitive roots" {
  let module_ = @wat.parse(
    (
      #|(module (type $node (struct (field (mut (ref null $node))) (field eqref))))
    ),
  )
  let store = @runtime.Store::with_c_heap()
  defer store.close()
  store.set_module_types(module_.types, rec_groups=module_.type_rec_groups)
  let first = store.alloc_struct(0, [Null, I31(-1)])
  let second = store.alloc_struct(0, [StructRef(first), I31(-7)])
  store.struct_set(first, 0, StructRef(second))
  defer runtime_fail_native_allocation(0)
  runtime_fail_native_allocation(1)
  let rejected = store.collect_garbage(additional_roots=[StructRef(first)])
  runtime_fail_native_allocation(0)
  assert_eq(rejected, -1)
  assert_eq(store.struct_get(first, 1), I31(-1))
  let roots = store.collect_roots([StructRef(first)])
  assert_eq(roots.length(), 2)
  assert_true(
    roots.contains(StructRef(first)) && roots.contains(StructRef(second)),
  )
  assert_eq(store.collect_garbage(additional_roots=[StructRef(first)]), 0)
  assert_eq(store.struct_get(second, 1), I31(-7))
  assert_eq(store.collect_garbage(), 2)
}

///|
test "typed continuation fields retain interpreter owned continuation handles" {
  let module_ = @wat.parse(
    (
      #|(module (type $f (func (result i32))) (type $c (cont $f))
      #| (type $box (struct (field (ref $c))))
      #| (func $body (result i32) i32.const 42) (elem declare func $body)
      #| (func (export "make") (result (ref $c)) (cont.new $c (ref.func $body)))
      #| (func (export "resume") (param (ref $c)) (result i32) (resume $c (local.get 0))))
    ),
  )
  let store = @runtime.Store::with_c_heap()
  defer store.close()
  let instance = @executor.instantiate_module_with_imports(
    store,
    module_,
    Imports(store),
  )
  let value = @executor.call_exported_func(store, instance, "make", [])[0]
  let box = store.alloc_struct(2, [value], instance~)
  store.collect_garbage(additional_roots=[StructRef(box)]) |> ignore
  assert_eq(
    @executor.call_exported_func(store, instance, "resume", [
      store.struct_get(box, 0),
    ]),
    [I32(42)],
  )
}

///|
test "physical layout cache denial preserves canonical type identities" {
  let module_ = native_gc_allocation_module()
  let store = @runtime.Store::with_c_heap()
  defer store.close()
  let instance = @executor.instantiate_module_with_imports(
    store,
    module_,
    Imports(store),
  )
  defer runtime_fail_native_allocation(0)
  runtime_fail_native_allocation(1)
  let denied = store.native_type_indices(instance)
  runtime_fail_native_allocation(0)
  assert_eq(denied.length(), instance.types.length())
  assert_eq(store.native_type_indices(instance), denied)
}

///|
test "Linker rollback preserves escaped typed objects when root discovery fails" {
  let module_ = @wat.parse(
    "(module (type $node (struct (field (ref null $node)) (field i32))))",
  )
  defer runtime_fail_native_allocation(0)
  for deny in [false, true] {
    let budget = @runtime.ResourceBudget::new(gc_bytes=4096L)
    let store = @runtime.Store::with_c_heap(resource_budget=Some(budget))
    defer store.close()
    store.set_module_types(module_.types, rec_groups=module_.type_rec_groups)
    let linker = @runtime.Linker::with_store(store)
    defer linker.close()
    let global = @runtime.GlobalInstance::GlobalInstance(
      { value_type: AnyRef, mutable: true, },
      Null,
    )
    linker.add_global("host", "escaped", global)
    let transaction = @runtime.InstantiationTransaction::new()
    linker.register_rollback(transaction.registrar())
    let child = store.alloc_struct(0, [Null, I32(42)])
    let escaped = store.alloc_struct(0, [StructRef(child), I32(7)])
    let unused = store.alloc_struct(0, [Null, I32(99)])
    global.set(StructRef(escaped))
    if deny {
      runtime_fail_native_allocation(1)
    }
    transaction.rollback()
    runtime_fail_native_allocation(0)
    assert_eq(global.get(), StructRef(escaped))
    assert_true(store.is_gc_valid(escaped))
    assert_true(store.is_gc_valid(child))
    assert_eq(store.struct_get(escaped, 0), StructRef(child))
    assert_eq(store.struct_get(child, 1), I32(42))
    // Failed discovery must defer reclamation, not treat its partial graph as
    // complete. Successful discovery must still reclaim provisional garbage.
    assert_eq(store.is_gc_valid(unused), deny)
    let retry = @runtime.InstantiationTransaction::new()
    linker.register_rollback(retry.registrar())
    let next_unused = store.alloc_struct(0, [Null, I32(1)])
    retry.rollback()
    assert_false(store.is_gc_valid(next_unused))
    assert_eq(store.struct_get(child, 1), I32(42))
    global.set(Null)
    assert_eq(store.collect_garbage(), if deny { 3 } else { 2 })
    assert_eq(budget.used(GcBytes), 0L)
    let replacement = store.alloc_struct(0, [Null, I32(43)])
    assert_eq(store.struct_get(replacement, 1), I32(43))
  }
}

///|
test "public root collection rejects empty and partially discovered native graphs" {
  let module_ = @wat.parse(
    "(module (type $node (struct (field (ref null $node)))))",
  )
  let store = @runtime.Store::with_c_heap()
  defer store.close()
  store.set_module_types(module_.types, rec_groups=module_.type_rec_groups)
  let mut root : @types.Value = Null
  for _ in 0..<40 {
    root = StructRef(store.alloc_struct(0, [root]))
  }
  defer runtime_fail_native_allocation(0)
  // The second queue allocation fails after 32 objects were discovered.
  for attempt in [1, 2] {
    runtime_fail_native_allocation(attempt)
    try store.collect_roots([root]) catch {
      UndefinedElement => ()
      error => fail(error.to_string())
    } noraise {
      _ => fail("incomplete discovery returned a root set")
    }
    runtime_fail_native_allocation(0)
    assert_eq(store.collect_roots([root]).length(), 40)
    assert_eq(store.collect_garbage(additional_roots=[root]), 0)
  }
  assert_eq(store.collect_garbage(), 40)
}
