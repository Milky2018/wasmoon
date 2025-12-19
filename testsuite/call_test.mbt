///|
test "call: f32 identity via direct call" {
  let source =
    #|(module
    #|  (func $id-f32 (param f32) (result f32) (local.get 0))
    #|  (func (export "type-first-f32") (result f32) (call $id-f32 (f32.const 1.32)))
    #|)
  let result = compare_jit_interp(source, "type-first-f32", [])
  inspect(result, content="matched")
}

///|
test "call: f64 identity via direct call" {
  let source =
    #|(module
    #|  (func $id-f64 (param f64) (result f64) (local.get 0))
    #|  (func (export "type-first-f64") (result f64) (call $id-f64 (f64.const 1.64)))
    #|)
  let result = compare_jit_interp(source, "type-first-f64", [])
  inspect(result, content="matched")
}

///|
test "call: f32 second arg" {
  let source =
    #|(module
    #|  (func $f64-f32 (param f64 f32) (result f32) (local.get 1))
    #|  (func (export "type-second-f32") (result f32)
    #|    (call $f64-f32 (f64.const 64) (f32.const 32)))
    #|)
  let result = compare_jit_interp(source, "type-second-f32", [])
  inspect(result, content="matched")
}

///|
test "call: f64 second arg" {
  let source =
    #|(module
    #|  (func $i64-f64 (param i64 f64) (result f64) (local.get 1))
    #|  (func (export "type-second-f64") (result f64)
    #|    (call $i64-f64 (i64.const 64) (f64.const 64.1)))
    #|)
  let result = compare_jit_interp(source, "type-second-f64", [])
  inspect(result, content="matched")
}

///|
test "call: multi return i32 f64" {
  let source =
    #|(module
    #|  (func $id-i32-f64 (param i32 f64) (result i32 f64)
    #|    (local.get 0) (local.get 1))
    #|  (func (export "type-all-i32-f64") (result i32 f64)
    #|    (call $id-i32-f64 (i32.const 32) (f64.const 1.64)))
    #|)
  let result = compare_jit_interp(source, "type-all-i32-f64", [])
  inspect(result, content="matched")
}

///|
test "call: simple f64 f32 return" {
  let source =
    #|(module
    #|  (func (export "test") (result f64 f32)
    #|    (f64.const 2.0)
    #|    (f32.const 1.0))
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
test "call: direct swap-f32-f64 host call" {
  let source =
    #|(module
    #|  (func (export "swap") (param f32 f64) (result f64 f32)
    #|    (local.get 1) (local.get 0))
    #|)
  let result = compare_jit_interp(source, "swap", [F32(1.0), F64(2.0)])
  inspect(result, content="matched")
}

///|
test "call: swap f32 f64" {
  let source =
    #|(module
    #|  (func $swap-f32-f64 (param f32 f64) (result f64 f32)
    #|    (local.get 1) (local.get 0))
    #|  (func (export "type-all-f32-f64") (result f64 f32)
    #|    (call $swap-f32-f64 (f32.const 1) (f64.const 2)))
    #|)
  let result = compare_jit_interp(source, "type-all-f32-f64", [])
  inspect(result, content="matched")
}

///|
test "call: swap f64 i32" {
  let source =
    #|(module
    #|  (func $swap-f64-i32 (param f64 i32) (result i32 f64)
    #|    (local.get 1) (local.get 0))
    #|  (func (export "type-all-f64-i32") (result i32 f64)
    #|    (call $swap-f64-i32 (f64.const 1) (i32.const 2)))
    #|)
  let result = compare_jit_interp(source, "type-all-f64-i32", [])
  inspect(result, content="matched")
}

///|
test "call: direct call with table present" {
  let source =
    #|(module
    #|  (func $const-i32 (result i32) (i32.const 306))
    #|  (table funcref (elem $const-i32))
    #|  (func (export "test") (result i32) (call $const-i32))
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
test "call: f32 call with table present" {
  let source =
    #|(module
    #|  (func $id-f32 (param f32) (result f32) (local.get 0))
    #|  (table funcref (elem $id-f32))
    #|  (func (export "test") (result f32) (call $id-f32 (f32.const 1.32)))
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
test "call: recursive factorial" {
  let source =
    #|(module
    #|  (func $fac (export "fac") (param i64) (result i64)
    #|    (if (result i64) (i64.eqz (local.get 0))
    #|      (then (i64.const 1))
    #|      (else
    #|        (i64.mul
    #|          (local.get 0)
    #|          (call $fac (i64.sub (local.get 0) (i64.const 1)))))))
    #|)
  let result = compare_jit_interp(source, "fac", [I64(5)])
  inspect(result, content="matched")
}

///|
test "call: mutually recursive even/odd" {
  let source =
    #|(module
    #|  (func $even (export "even") (param i64) (result i32)
    #|    (if (result i32) (i64.eqz (local.get 0))
    #|      (then (i32.const 44))
    #|      (else (call $odd (i64.sub (local.get 0) (i64.const 1))))))
    #|  (func $odd (export "odd") (param i64) (result i32)
    #|    (if (result i32) (i64.eqz (local.get 0))
    #|      (then (i32.const 99))
    #|      (else (call $even (i64.sub (local.get 0) (i64.const 1))))))
    #|)
  let result1 = compare_jit_interp(source, "even", [I64(0)])
  inspect(result1, content="matched")
  let result2 = compare_jit_interp(source, "even", [I64(1)])
  inspect(result2, content="matched")
  let result3 = compare_jit_interp(source, "odd", [I64(0)])
  inspect(result3, content="matched")
  let result4 = compare_jit_interp(source, "odd", [I64(1)])
  inspect(result4, content="matched")
}

///|
test "call: as-convert-operand" {
  let source =
    #|(module
    #|  (func $dummy (param i32) (result i32) (local.get 0))
    #|  (func (export "as-convert-operand") (result i64)
    #|    (block (result i64) (i64.extend_i32_s (call $dummy (i32.const 1))))
    #|  )
    #|)
  let result = compare_jit_interp(source, "as-convert-operand", [])
  inspect(result, content="matched")
}

///|
test "call: as-memory-grow-value" {
  let source =
    #|(module
    #|  (memory 1)
    #|  (func $const-i32 (result i32) (i32.const 0x132))
    #|  (func (export "as-memory.grow-value") (result i32)
    #|    (memory.grow (call $const-i32))
    #|  )
    #|)
  let result = compare_jit_interp(source, "as-memory.grow-value", [])
  inspect(result, content="matched")
}

///|
test "call: return-from-long-argument-list" {
  let source =
    #|(module
    #|  (func $return-from-long-argument-list-helper
    #|        (param f32 i32 i32 f64 f32 f32 f32 f64 f32 i32 i32 f32 f64 i64 i64 i32 i64 i64 f32 i64 i64 i64 i32 f32 f32 f32 f64 f32 i32 i64 f32 f64 f64 f32 i32 f32 f32 f64 i64 f64 i32 i64 f32 f64 i32 i32 i32 i64 f64 i32 i64 i64 f64 f64 f64 f64 f64 f64 i32 f32 f64 f64 i32 i64 f32 f32 f32 i32 f64 f64 f64 f64 f64 f32 i64 i64 i32 i32 i32 f32 f64 i32 i64 f32 f32 f32 i32 i32 f32 f64 i64 f32 f64 f32 f32 f32 i32 f32 i64 i32)
    #|        (result i32)
    #|    (local.get 99)
    #|  )
    #|  (func (export "return-from-long-argument-list") (param i32) (result i32)
    #|    (call $return-from-long-argument-list-helper
    #|      (f32.const 0) (i32.const 0) (i32.const 0) (f64.const 0) (f32.const 0) (f32.const 0) (f32.const 0) (f64.const 0) (f32.const 0) (i32.const 0)
    #|      (i32.const 0) (f32.const 0) (f64.const 0) (i64.const 0) (i64.const 0) (i32.const 0) (i64.const 0) (i64.const 0) (f32.const 0) (i64.const 0)
    #|      (i64.const 0) (i64.const 0) (i32.const 0) (f32.const 0) (f32.const 0) (f32.const 0) (f64.const 0) (f32.const 0) (i32.const 0) (i64.const 0)
    #|      (f32.const 0) (f64.const 0) (f64.const 0) (f32.const 0) (i32.const 0) (f32.const 0) (f32.const 0) (f64.const 0) (i64.const 0) (f64.const 0)
    #|      (i32.const 0) (i64.const 0) (f32.const 0) (f64.const 0) (i32.const 0) (i32.const 0) (i32.const 0) (i64.const 0) (f64.const 0) (i32.const 0)
    #|      (i64.const 0) (i64.const 0) (f64.const 0) (f64.const 0) (f64.const 0) (f64.const 0) (f64.const 0) (f64.const 0) (i32.const 0) (f32.const 0)
    #|      (f64.const 0) (f64.const 0) (i32.const 0) (i64.const 0) (f32.const 0) (f32.const 0) (f32.const 0) (i32.const 0) (f64.const 0) (f64.const 0)
    #|      (f64.const 0) (f64.const 0) (f64.const 0) (f32.const 0) (i64.const 0) (i64.const 0) (i32.const 0) (i32.const 0) (i32.const 0) (f32.const 0)
    #|      (f64.const 0) (i32.const 0) (i64.const 0) (f32.const 0) (f32.const 0) (f32.const 0) (i32.const 0) (i32.const 0) (f32.const 0) (f64.const 0)
    #|      (i64.const 0) (f32.const 0) (f64.const 0) (f32.const 0) (f32.const 0) (f32.const 0) (i32.const 0) (f32.const 0) (i64.const 0) (local.get 0))
    #|  )
    #|)
  let result = compare_jit_interp(source, "return-from-long-argument-list", [
    I32(42),
  ])
  inspect(result, content="matched")
}
