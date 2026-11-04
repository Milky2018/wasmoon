///|
fn allocation_operand_roots_module() -> @types.Module raise {
  let source =
    #|(module
    #| (type $leaf (struct (field i32)))
    #| (type $box (struct (field f64)))
    #| (type $array (array (mut f64)))
    #| (type $mixed (struct (field i64) (field (ref $leaf)) (field i32)))
    #| (global $box (export "box") (mut (ref null $box)) (ref.null $box))
    #| (global $array (export "last-array") (mut (ref null $array)) (ref.null $array))
    #| (func (export "struct") (param $bits i64) (result i64)
    #|  local.get $bits f64.reinterpret_i64 struct.new $box global.set $box
    #|  global.get $box struct.get $box 0 i64.reinterpret_f64)
    #| (func (export "array") (param $bits i64) (result i64)
    #|  local.get $bits f64.reinterpret_i64 i32.const 2 array.new $array global.set $array
    #|  global.get $array i32.const 1 array.get $array i64.reinterpret_f64)
    #| (func (export "fixed") (param $bits i64) (result i64)
    #|  f64.const 42 local.get $bits f64.reinterpret_i64 array.new_fixed $array 2 global.set $array
    #|  global.get $array i32.const 1 array.get $array i64.reinterpret_f64)
    #| (func (export "mixed") (param $child (ref $leaf)) (param $bits i64) (result (ref $mixed))
    #|  local.get $bits local.get $child i32.const 7 struct.new $mixed))
  @wat.parse(source)
}

///|
test "numeric allocation operands cannot masquerade as native reference roots" {
  let module_ = allocation_operand_roots_module()
  @validator.validate_module(module_)
  for opt_level in [0, 2, 3] {
    for native in [false, true] {
      let store = @runtime.Store::with_c_heap(
        resource_budget=Some(@runtime.ResourceBudget::new(gc_bytes=4096L)),
      )
      defer store.close()
      let instance = @executor.instantiate_module_with_imports(
        store,
        module_,
        Imports(store),
      )
      let context = if native {
        Some(build_gc_root_context(module_, instance, store, opt_level~))
      } else {
        None
      }
      defer (if context is Some(context) { context.close() })
      defer @wasmoon_jit.gc_debug_set_fail_alloc(0)
      for index, name in ["struct", "array", "fixed"] {
        // Include both an apparently well-formed exception token and the
        // floating-point payload observed in the dense-collection reproduction.
        for bits in [0x1000000000000001L, 0x12869794a160cb58L, -7L] {
          let result = if context is Some(context) {
            @wasmoon_jit.gc_debug_set_fail_alloc(1)
            context.call_core_func(store, instance, index, [I64(bits)])
          } else {
            @executor.call_exported_func(store, instance, name, [I64(bits)])
          }
          @wasmoon_jit.gc_debug_set_fail_alloc(0)
          assert_eq(
            result,
            [I64(bits)],
            msg="\{name}, native=\{native}, level=\{opt_level}",
          )
        }
      }
      assert_true(store.native_heap().unwrap().verify())
    }
  }
}

///|
test "mixed allocation operands retain references while excluding numeric aliases" {
  let module_ = allocation_operand_roots_module()
  @validator.validate_module(module_)
  for opt_level in [0, 2, 3] {
    let store = @runtime.Store::with_c_heap(
      resource_budget=Some(@runtime.ResourceBudget::new(gc_bytes=4096L)),
    )
    defer store.close()
    let instance = @executor.instantiate_module_with_imports(
      store,
      module_,
      Imports(store),
    )
    let context = build_gc_root_context(module_, instance, store, opt_level~)
    defer context.close()
    defer @wasmoon_jit.gc_debug_set_fail_alloc(0)
    let child = store.alloc_struct(0, [I32(42)], instance~)
    let bits = 0x12869794a160cb58L
    @wasmoon_jit.gc_debug_set_fail_alloc(1)
    let result = context.call_core_func(store, instance, 3, [
      StructRef(child),
      I64(bits),
    ])
    @wasmoon_jit.gc_debug_set_fail_alloc(0)
    guard result is [StructRef(parent)] else { fail("missing mixed parent") }
    assert_eq(store.struct_get(parent, 0), I64(bits))
    assert_eq(store.struct_get(parent, 1), StructRef(child))
    assert_eq(store.struct_get(child, 0), I32(42))
    let roots = store.pin_gc_roots(result)
    defer roots.release()
    assert_eq(store.collect_garbage(), 0)
    assert_eq(store.struct_get(child, 0), I32(42))
    roots.release()
    assert_eq(store.collect_garbage(), 2)
  }
}
