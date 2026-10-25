///|
test "segment constructors use canonical compact layouts in both engines" {
  let source =
    #|(module
    #| (type $b (array (mut i8))) (type $h (array (mut i16)))
    #| (type $i (array (mut i32))) (type $l (array (mut i64)))
    #| (type $f (array (mut f32))) (type $d (array (mut f64)))
    #| (type $s (struct (field i32)))
    #| (type $r (array (mut (ref $s))))
    #| (data $bytes "\2a\00\00\00\00\00\00\00")
    #| (elem $objects (ref $s) (item (struct.new $s (i32.const 42))))
    #| (func (export "b") (result (ref $b)) i32.const 0 i32.const 8 array.new_data $b $bytes)
    #| (func (export "h") (result (ref $h)) i32.const 0 i32.const 4 array.new_data $h $bytes)
    #| (func (export "i") (result (ref $i)) i32.const 0 i32.const 2 array.new_data $i $bytes)
    #| (func (export "l") (result (ref $l)) i32.const 0 i32.const 1 array.new_data $l $bytes)
    #| (func (export "f") (result (ref $f)) i32.const 0 i32.const 2 array.new_data $f $bytes)
    #| (func (export "d") (result (ref $d)) i32.const 0 i32.const 1 array.new_data $d $bytes)
    #| (func (export "r") (result (ref $r)) i32.const 0 i32.const 1 array.new_elem $r $objects))
  let module_ = @wat.parse(source)
  @validator.validate_module(module_)
  for opt_level in [0, 2, 3] {
    for native in [false, true] {
      let store = @runtime.Store::with_c_heap()
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
      let heap = store.native_heap().unwrap()
      for index, name in ["b", "h", "i", "l", "f", "d", "r"] {
        let before = heap.get_size()
        let result = if context is Some(context) {
          context.call_core_func(store, instance, index, [])
        } else {
          @executor.call_exported_func(store, instance, name, [])
        }
        guard result is [ArrayRef(array)] else { fail("missing array result") }
        assert_true(
          heap.runtime_type(array) >= 0,
          msg="native=\{native}, level=\{opt_level}, kind=\{name}",
        )
        assert_eq(heap.get_size() - before, 48L)
        let rooted = store.pin_gc_roots(result)
        defer rooted.release()
        store.collect_garbage() |> ignore
        let value = store.array_get(array, 0)
        match value {
          I32(value) => assert_eq(value, 42)
          I64(value) => assert_eq(value, 42L)
          F32(value) => assert_eq(value.reinterpret_as_int(), 42)
          F64(value) => assert_eq(value.reinterpret_as_int64(), 42L)
          StructRef(child) => assert_eq(store.struct_get(child, 0), I32(42))
          _ => fail("incorrect segment element representation")
        }
        assert_true(heap.verify())
        rooted.release()
      }
    }
  }
}
