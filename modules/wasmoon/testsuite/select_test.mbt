///|
/// Test basic select instruction
test "select_i32" {
  let source =
    #|(module
    #|  (func (export "select-i32") (param i32 i32 i32) (result i32)
    #|    (select (local.get 0) (local.get 1) (local.get 2))
    #|  )
    #|)
  let result = compare_jit_interp(source, "select-i32", [
    I32(10),
    I32(20),
    I32(1),
  ])
  inspect(result, content="matched")
}

///|
test "select_i32_false" {
  let source =
    #|(module
    #|  (func (export "select-i32") (param i32 i32 i32) (result i32)
    #|    (select (local.get 0) (local.get 1) (local.get 2))
    #|  )
    #|)
  let result = compare_jit_interp(source, "select-i32", [
    I32(10),
    I32(20),
    I32(0),
  ])
  inspect(result, content="matched")
}

///|
test "select_i64" {
  let source =
    #|(module
    #|  (func (export "select-i64") (param i64 i64 i32) (result i64)
    #|    (select (local.get 0) (local.get 1) (local.get 2))
    #|  )
    #|)
  let result = compare_jit_interp(source, "select-i64", [
    I64(100L),
    I64(200L),
    I32(1),
  ])
  inspect(result, content="matched")
}

///|
test "select_f32" {
  let source =
    #|(module
    #|  (func (export "select-f32") (param f32 f32 i32) (result f32)
    #|    (select (local.get 0) (local.get 1) (local.get 2))
    #|  )
    #|)
  let result = compare_jit_interp(source, "select-f32", [
    F32(1.5),
    F32(2.5),
    I32(1),
  ])
  inspect(result, content="matched")
}

///|
test "select_f64" {
  let source =
    #|(module
    #|  (func (export "select-f64") (param f64 f64 i32) (result f64)
    #|    (select (local.get 0) (local.get 1) (local.get 2))
    #|  )
    #|)
  let result = compare_jit_interp(source, "select-f64", [
    F64(3.14),
    F64(2.71),
    I32(0),
  ])
  inspect(result, content="matched")
}

///|
test "select_unreachable" {
  // This test is from the select.wast file
  // After unreachable, the stack is polymorphic, so select with fewer operands should work
  // The function should trap at runtime when called (on the unreachable instruction)
  let source =
    #|(module
    #|  (func (export "select-unreached")
    #|    (unreachable) (select)
    #|    (unreachable) (i32.const 0) (select)
    #|    (unreachable) (i32.const 0) (i32.const 0) (select)
    #|    (unreachable) (i32.const 0) (i32.const 0) (i32.const 0) (select)
    #|    (unreachable) (f32.const 0) (i32.const 0) (select)
    #|    (unreachable)
    #|  )
    #|)
  let result = compare_jit_interp(source, "select-unreached", [])
  // Both should trap, so they match
  inspect(result, content="matched")
}
