///|
test "checked struct views preserve callable opaque and heap reference carriers" {
  let module_ = @wat.parse(
    (
      #|(module
      #| (type $f (func (param i64) (result i64)))
      #| (type $child (struct (field i64)))
      #| (type $box (struct (field (mut (ref null $f))) (field (mut externref))
      #|  (field (mut i64)) (field (mut (ref null $child)))))
      #| (func $add (type $f) local.get 0 i64.const 5 i64.add)
      #| (elem declare func $add)
      #| (func $read (param (ref $box)) (result i64)
      #|  local.get 0 struct.get $box 2 local.get 0 struct.get $box 0 ref.as_non_null call_ref $f
      #|  local.get 0 struct.get $box 3 struct.get $child 0 i64.add
      #|  local.get 0 struct.get $box 1 any.convert_extern ref.cast (ref i31) i31.get_u i64.extend_i32_u i64.add)
      #| (func (export "probe") (result i64) (local $b (ref $box))
      #|  ref.func $add ref.null extern i64.const 37 i64.const 42 struct.new $child struct.new $box local.set $b
      #|  local.get $b i32.const 17 ref.i31 extern.convert_any struct.set $box 1
      #|  local.get $b ref.func $add struct.set $box 0
      #|  local.get $b call $read))
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
    assert_eq(context.call_core_func(store, instance, 2, []), [I64(101L)])
    assert_eq(store.collect_garbage(), 2)
  }
}

///|
test "large typed structs keep checked suffix and subtype layout access" {
  let prefix = Array::make(17, "(field (mut i64))").join(" ")
  let source =
    $|(module
    $| (type $base (sub (struct \{prefix})))
    $| (type $derived (sub $base (struct \{prefix} (field (mut i64)))))
    $| (func $read (param (ref $base)) (result i64)
    $|  local.get 0 struct.get $base 8 local.get 0 struct.get $base 16 i64.add)
    $| (func (export "probe") (result i64) (local $n (ref $derived))
    $|  struct.new_default $derived local.set $n
    $|  local.get $n i64.const 42 struct.set $derived 8
    $|  local.get $n i64.const 7 struct.set $derived 16
    $|  local.get $n call $read))
  let module_ = @wat.parse(source)
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
    assert_eq(context.call_core_func(store, instance, 1, []), [I64(49L)])
    assert_eq(store.collect_garbage(), 1)
  }
}
