///|
test "f32 identity multiple values" {
  let source =
    #|(module
    #|  (func (export "id") (param f32) (result f32)
    #|    (local.get 0))
    #|)
  // Test with multiple values to ensure it's not a fluke
  let r1 = compare_jit_interp(source, "id", [F32(1.0)])
  let r2 = compare_jit_interp(source, "id", [F32(2.0)])
  let r3 = compare_jit_interp(source, "id", [F32(123.456)])
  inspect(
    r1.to_string(),
    content=(
      #|JIT: F32(1)
      #|Interpreter: F32(1)
      #|Result: MATCH
    ),
  )
  inspect(
    r2.to_string(),
    content=(
      #|JIT: F32(2)
      #|Interpreter: F32(2)
      #|Result: MATCH
    ),
  )
  inspect(
    r3.to_string(),
    content=(
      #|JIT: F32(123.45600128173828)
      #|Interpreter: F32(123.45600128173828)
      #|Result: MATCH
    ),
  )
}

///|
test "f32 add with prints" {
  let source =
    #|(module
    #|  (func (export "add") (param f32) (param f32) (result f32)
    #|    (f32.add (local.get 0) (local.get 1)))
    #|)
  // Test with very simple values
  let a = (1.0 : Float)
  let b = (2.0 : Float)
  let a_bits = a.reinterpret_as_int()
  let b_bits = b.reinterpret_as_int()
  inspect(a_bits, content="1065353216") // Should be 0x3F800000 = 1065353216
  inspect(b_bits, content="1073741824") // Should be 0x40000000 = 1073741824
  let result = compare_jit_interp(source, "add", [F32(a), F32(b)])
  inspect(
    result.to_string(),
    content=(
      #|JIT: F32(3)
      #|Interpreter: F32(3)
      #|Result: MATCH
    ),
  )
}
