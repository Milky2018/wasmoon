///|
test "JIT floating lane replacement preserves aliased scalar inputs" {
  let args : Array[@types.Value] = [
    V128(b"\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10"),
    V128(b"\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1a\x1b\x1c\x1d\x1e\x1f\x20"),
  ]
  for lane in [("f32x4", 4), ("f64x2", 2)] {
    let (lane_type, lane_count) = lane
    for destination in 0..<lane_count {
      for source_lane in 0..<lane_count {
        let source = "(module (func (export \"run\") (param v128 v128) (result v128) " +
          "(\{lane_type}.replace_lane \{destination} (local.get 0) " +
          "(\{lane_type}.extract_lane \{source_lane} (local.get 1)))))"
        let comparison = compare_jit_interp(source, "run", args)
        assert_true(compare_result_is_match(comparison))
        let module_ = @wat.parse(source)
        @validator.validate_module(module_)
        let store = @runtime.Store::with_c_heap()
        defer store.close()
        let instance = @executor.instantiate_module_with_imports(
          store,
          module_,
          Imports(),
        )
        let expected = @executor.call_func_by_index(store, instance, 0, args)
        let context = prepare_async_jit_context(
          module_,
          instance,
          store,
          cooperative=true,
        )
        defer context.close()
        let actual = context.call_core_func(store, instance, 0, args)
        assert_eq(actual, expected)
      }
    }
  }
}
