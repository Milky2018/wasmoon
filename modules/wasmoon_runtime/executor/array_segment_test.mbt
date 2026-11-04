///|
fn vector_segment_module() -> String {
  (
    #|(module
    #| (type $a (array (mut v128)))
    #| (data $d "\ff\01\02\03\04\05\06\07\08\11\12\13\14\15\16\17\18\21\22\23\24\25\26\27\28\31\32\33\34\35\36\37\38")
    #| (global $out (ref $a) (array.new $a (v128.const i64x2 -1 -2) (i32.const 4)))
    #| (func (export "new") (param i32 i32) (result (ref $a))
    #|  local.get 0 local.get 1 array.new_data $a $d)
    #| (func (export "init") (param i32 i32 i32)
    #|  global.get $out local.get 0 local.get 1 local.get 2 array.init_data $a $d)
    #| (func (export "get") (param i32) (result v128)
    #|  global.get $out local.get 0 array.get $a)
    #| (func (export "null")
    #|  ref.null $a i32.const 0 i32.const 0 i32.const 0 array.init_data $a $d)
    #| (func (export "drop") data.drop $d))
  )
}

///|
test "vector segment construction preserves both words and byte strides" {
  let store = @runtime.Store()
  defer store.close()
  let module_ = @wat.parse(vector_segment_module())
  @validator.validate_module(module_)
  let instance = @executor.instantiate_module_with_imports(
    store,
    module_,
    Imports(store),
  )
  let result = @executor.call_exported_func(store, instance, "new", [
    I32(1),
    I32(2),
  ])
  guard result is [ArrayRef(array)] else { fail("missing vector array") }
  let roots = store.pin_gc_roots(result)
  defer roots.release()
  store.collect_garbage() |> ignore
  assert_eq(
    store.array_get(array, 0),
    V128(b"\x01\x02\x03\x04\x05\x06\x07\x08\x11\x12\x13\x14\x15\x16\x17\x18"),
  )
  assert_eq(
    store.array_get(array, 1),
    V128(b"\x21\x22\x23\x24\x25\x26\x27\x28\x31\x32\x33\x34\x35\x36\x37\x38"),
  )
}

///|
test "vector segment initialization preserves adjacent values and failed ranges" {
  let store = @runtime.Store()
  defer store.close()
  let instance = @executor.instantiate_module_with_imports(
    store,
    @wat.parse(vector_segment_module()),
    Imports(store),
  )
  assert_eq(
    @executor.call_exported_func(store, instance, "init", [
      I32(1),
      I32(1),
      I32(2),
    ]),
    [],
  )
  let before = Array::makei(4, i => {
    @executor.call_exported_func(store, instance, "get", [I32(i)])
  })
  assert_eq(before[1], [
    V128(b"\x01\x02\x03\x04\x05\x06\x07\x08\x11\x12\x13\x14\x15\x16\x17\x18"),
  ])
  assert_eq(before[2], [
    V128(b"\x21\x22\x23\x24\x25\x26\x27\x28\x31\x32\x33\x34\x35\x36\x37\x38"),
  ])
  assert_eq(before[0], [V128(@types.int64_pair_to_v128_le(-1L, -2L))])
  assert_eq(before[3], before[0])
  try
    @executor.call_exported_func(store, instance, "init", [
      I32(1),
      I32(2),
      I32(2),
    ])
  catch {
    OutOfBoundsMemoryAccess => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("vector source bounds were truncated")
  }
  try
    @executor.call_exported_func(store, instance, "init", [
      I32(3),
      I32(1),
      I32(2),
    ])
  catch {
    OutOfBoundsArrayAccess => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("vector destination bounds were ignored")
  }
  store.collect_garbage() |> ignore
  for i in 0..<4 {
    assert_eq(
      @executor.call_exported_func(store, instance, "get", [I32(i)]),
      before[i],
    )
  }
}

///|
test "vector segment drop and null retain zero-length trap ordering" {
  let store = @runtime.Store()
  defer store.close()
  let instance = @executor.instantiate_module_with_imports(
    store,
    @wat.parse(vector_segment_module()),
    Imports(store),
  )
  @executor.call_exported_func(store, instance, "drop", []) |> ignore
  assert_eq(
    @executor.call_exported_func(store, instance, "init", [
      I32(4),
      I32(0),
      I32(0),
    ]),
    [],
  )
  try
    @executor.call_exported_func(store, instance, "new", [I32(0), I32(1)])
  catch {
    OutOfBoundsMemoryAccess => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("dropped segment supplied vector bytes")
  }
  try @executor.call_exported_func(store, instance, "null", []) catch {
    NullReference => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("zero-length vector init accepted null")
  }
}
