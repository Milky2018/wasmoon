///|
test "f32 identity function" {
  let source =
    #|(module
    #|  (func (export "id") (param f32) (result f32)
    #|    (local.get 0))
    #|)
  let result = compare_jit_interp(source, "id", [F32(3.14)])
  inspect(
    result.to_string(),
    content=(
      #|JIT: F32(3.140000104904175)
      #|Interpreter: F32(3.140000104904175)
      #|Result: MATCH
    ),
  )
  inspect(result.matched(), content="true")
}

///|
test "f32 add simple" {
  let source =
    #|(module
    #|  (func (export "add") (param f32) (param f32) (result f32)
    #|    (f32.add (local.get 0) (local.get 1)))
    #|)
  let result = compare_jit_interp(source, "add", [F32(1.5), F32(2.5)])
  inspect(
    result.to_string(),
    content=(
      #|JIT: F32(4)
      #|Interpreter: F32(4)
      #|Result: MATCH
    ),
  )
  inspect(result.matched(), content="true")
}

///|
test "f32 mul simple" {
  let source =
    #|(module
    #|  (func (export "mul") (param f32) (param f32) (result f32)
    #|    (f32.mul (local.get 0) (local.get 1)))
    #|)
  let result = compare_jit_interp(source, "mul", [F32(2.0), F32(3.0)])
  inspect(
    result.to_string(),
    content=(
      #|JIT: F32(6)
      #|Interpreter: F32(6)
      #|Result: MATCH
    ),
  )
  inspect(result.matched(), content="true")
}
