///|
test "loop-cached references reset at calls and remain valid across invocations and GC" {
  for
    (mutation, expected) in [
      ("", 50),
      ("local.get $p local.get $i i32.const 1 i32.add call $replace", 55),
    ] {
    let source =
      $|(module
      $| (type $a (array (mut i32)))
      $| (type $s (struct (field (mut (ref $a)))))
      $| (func $replace (param $p (ref $s)) (param $n i32)
      $|  local.get $p i32.const 7 local.get $n array.new $a struct.set $s 0)
      $| (func (export "test") (result i32)
      $|  (local $p (ref $s)) (local $i i32) (local $sum i32)
      $|  i32.const 7 i32.const 5 array.new $a struct.new $s local.set $p
      $|  (loop $again
      $|   \{mutation}
      $|   local.get $sum local.get $p struct.get $s 0 array.len i32.add local.set $sum
      $|   local.get $i i32.const 1 i32.add local.tee $i i32.const 10 i32.lt_u br_if $again)
      $|  local.get $sum))
    let module_ = @wat.parse(source)
    @validator.validate_module(module_)
    for opt_level in [0, 2, 3] {
      let budget = @runtime.ResourceBudget::new(
        gc_bytes=16384L,
        gc_objects=256L,
      )
      let store = @runtime.Store::with_c_heap(resource_budget=Some(budget))
      defer store.close()
      let instance = @executor.instantiate_module_with_imports(
        store,
        module_,
        Imports(store),
      )
      let context = build_gc_root_context(module_, instance, store, opt_level~)
      defer context.close()
      for _ in 0..<3 {
        assert_eq(context.call_core_func(store, instance, 1, []), [
          I32(expected),
        ])
        store.collect_garbage() |> ignore
        assert_eq(budget.used(GcBytes), 0L)
      }
    }
  }
}
