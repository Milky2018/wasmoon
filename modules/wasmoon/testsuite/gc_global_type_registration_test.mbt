///|
test "GC global type registration preserves JIT and interpreter subtype layouts" {
  let source =
    #|(module
    #| (type $base (sub (struct (field i32))))
    #| (type $child (sub $base (struct (field i32) (field i64))))
    #| (type $array (array (mut (ref null $base))))
    #| (global $child (ref $child) (struct.new $child (i32.const 42) (i64.const 99)))
    #| (global $array (ref $array) (array.new $array (global.get $child) (i32.const 1)))
    #| (func (export "test") (result i32)
    #|   global.get $child ref.test (ref $base)
    #|   global.get $array i32.const 0 array.get $array ref.as_non_null struct.get $base 0
    #|   i32.add))
  let (store, instance) = @executor.instantiate_module(@wat.parse(source))
  defer store.close()
  assert_eq(@executor.call_exported_func(store, instance, "test", []), [I32(43)])
  inspect(@testsuite.compare_jit_interp(source, "test", []), content="matched")
}
