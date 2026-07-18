///|
test "JIT: signed remainder handles the minimum value divided by minus one" {
  let source =
    #|(module
    #|  (func (export "i32_rem") (result i32)
    #|    (i32.rem_s (i32.const 0x80000000) (i32.const -1)))
    #|  (func (export "i64_rem") (result i64)
    #|    (i64.rem_s (i64.const 0x8000000000000000) (i64.const -1))))
  inspect(compare_jit_interp(source, "i32_rem", []), content="matched")
  inspect(compare_jit_interp(source, "i64_rem", []), content="matched")
}
