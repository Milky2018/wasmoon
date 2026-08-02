///|
test "compare releases temporary JIT table owners" {
  let baseline = @native_test_support.shared_indirect_table_live_count()
  let source =
    #|(module
    #|  (type $t (func (result i32)))
    #|  (table 1 funcref)
    #|  (elem (i32.const 0) $f)
    #|  (func $f (export "call") (type $t) (i32.const 7))
    #|)
  for _ in 0..<2 {
    let result = compare_jit_interp(source, "call", [])
    inspect(result.matched(), content="true")
    inspect(
      @native_test_support.shared_indirect_table_live_count() == baseline,
      content="true",
    )
  }
}
