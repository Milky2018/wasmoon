///|
test "reference tests preserve concrete abstract nullable and legacy predicates" {
  let module_ = @wat.parse(
    (
      #|(module
      #| (type $base (sub (struct (field (mut i64)))))
      #| (type $child (sub $base (struct (field (mut i64)) (field i32))))
      #| (type $wrong (struct (field f64)))
      #| (type $array (array (mut i32)))
      #| (func (export "classify") (param anyref) (result i32)
      #|   local.get 0 ref.test (ref $base)
      #|   local.get 0 ref.test (ref $child) i32.const 1 i32.shl i32.or
      #|   local.get 0 ref.test (ref null $base) i32.const 2 i32.shl i32.or
      #|   local.get 0 ref.test (ref array) i32.const 3 i32.shl i32.or
      #|   local.get 0 ref.test (ref eq) i32.const 4 i32.shl i32.or
      #|   local.get 0 ref.test (ref i31) i32.const 5 i32.shl i32.or
      #|   local.get 0 ref.test (ref struct) i32.const 6 i32.shl i32.or
      #|   local.get 0 ref.test (ref null none) i32.const 7 i32.shl i32.or)
      #| (func (export "cast") (param anyref) (result i32)
      #|   local.get 0 ref.cast (ref $base) drop i32.const 1))
    ),
  )
  @validator.validate_module(module_)
  for level in [0, 2, 3] {
    let store = @runtime.Store::with_c_heap()
    defer store.close()
    let instance = @executor.instantiate_module_with_imports(
      store,
      module_,
      Imports(store),
    )
    let context = build_gc_root_context(
      module_,
      instance,
      store,
      opt_level=level,
    )
    defer context.close()
    let base = store.alloc_struct(0, [I64(42L)], instance~)
    let child = store.alloc_struct(1, [I64(42L), I32(7)], instance~)
    let wrong = store.alloc_struct(2, [F64(3.0)], instance~)
    let array = store.alloc_array_repeated(3, 2, I32(11), instance~)
    let cases : Array[(Int64, @types.Value, Int32)] = [
      ((base + 1).to_int64() << 1, StructRef(base), 85),
      ((child + 1).to_int64() << 1, StructRef(child), 87),
      ((wrong + 1).to_int64() << 1, StructRef(wrong), 80),
      ((array + 1).to_int64() << 1, ArrayRef(array), 24),
      ((19L << 1) | 1L, I31(19), 48),
      (0L, Null, 132),
    ]
    for (raw, value, expected) in cases {
      assert_eq(
        context.jit_module.call_with_context(
          context.jit_module.get_func(0).unwrap(),
          [raw],
        ),
        [expected.to_int64()],
      )
      assert_eq(
        @executor.call_exported_func(store, instance, "classify", [value]),
        [I32(expected)],
      )
      let should_cast = (expected & 1) != 0
      try
        context.jit_module.call_with_context(
          context.jit_module.get_func(1).unwrap(),
          [raw],
        )
      catch {
        JITTrap(_) => assert_false(should_cast)
        error => fail(error.to_string())
      } noraise {
        result => {
          assert_true(should_cast)
          assert_eq(result, [1L])
        }
      }
    }
    let legacy = store
      .native_heap()
      .unwrap()
      .alloc_struct(1, [I64(17L), I32(8)])
    assert_eq(
      context.jit_module.call_with_context(
        context.jit_module.get_func(0).unwrap(),
        [(legacy + 1).to_int64() << 1],
      ),
      [87L],
    )
  }
}
