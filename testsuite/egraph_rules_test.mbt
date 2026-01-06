///|
/// E2E tests to verify egraph optimization rules are applied correctly
/// These tests check the IR output after optimization to confirm rules fired
///
/// Note: Currently only constant-producing rules are verified because
/// get_simplified_opcode only applies constant results back to the IR.

///|
/// Helper function to compile WAT to optimized IR and return the IR string
fn compile_and_optimize(source : String) -> String {
  let ir = @wat.parse(source) catch { _ => panic() }
  let func_code = ir.codes[0]
  let func_type_idx = ir.funcs[0]
  let func_type = ir.get_func_type(func_type_idx)
  let locals : Array[@types.ValueType] = []
  for loc in func_code.locals {
    locals.push(loc)
  }
  let translator = @ir.Translator::new(
    "test",
    func_type,
    locals,
    @types.extract_func_types(ir.types),
    ir.funcs.mapi(fn(i, _) { ir.funcs[i] }),
    0,
    [],
  )
  let ir_func = translator.translate(func_code.body)
  @ir.optimize(ir_func) |> ignore
  ir_func.to_string()
}

///|
/// Test: x - x → 0 (self-subtraction produces constant 0)
test "egraph: sub_self_to_zero" {
  let source =
    #|(module
    #|  (func (export "test") (param i32) (result i32)
    #|    (i32.sub (local.get 0) (local.get 0))
    #|  )
    #|)
  let ir = compile_and_optimize(source)
  // After optimization, should have Iconst(0) instead of Isub
  inspect(ir.contains("Iconst(0)"), content="true")
  inspect(ir.contains("Isub"), content="false")
}

///|
/// Test: x ^ x → 0 (self-xor produces constant 0)
test "egraph: xor_self_to_zero" {
  let source =
    #|(module
    #|  (func (export "test") (param i32) (result i32)
    #|    (i32.xor (local.get 0) (local.get 0))
    #|  )
    #|)
  let ir = compile_and_optimize(source)
  // After optimization, should have Iconst(0) instead of Bxor
  inspect(ir.contains("Iconst(0)"), content="true")
  inspect(ir.contains("Bxor"), content="false")
}

///|
/// Test: constant folding - 10 + 20 → 30
test "egraph: const_fold_add" {
  let source =
    #|(module
    #|  (func (export "test") (result i32)
    #|    (i32.add (i32.const 10) (i32.const 20))
    #|  )
    #|)
  let ir = compile_and_optimize(source)
  // After optimization, should be a single Iconst(30)
  inspect(ir.contains("Iconst(30)"), content="true")
  // Should NOT have separate constants or add
  inspect(ir.contains("Iadd"), content="false")
}

///|
/// Test: constant folding - 100 - 30 → 70
test "egraph: const_fold_sub" {
  let source =
    #|(module
    #|  (func (export "test") (result i32)
    #|    (i32.sub (i32.const 100) (i32.const 30))
    #|  )
    #|)
  let ir = compile_and_optimize(source)
  // After optimization, should be a single Iconst(70)
  inspect(ir.contains("Iconst(70)"), content="true")
  inspect(ir.contains("Isub"), content="false")
}

///|
/// Test: constant folding - 5 * 6 → 30
test "egraph: const_fold_mul" {
  let source =
    #|(module
    #|  (func (export "test") (result i32)
    #|    (i32.mul (i32.const 5) (i32.const 6))
    #|  )
    #|)
  let ir = compile_and_optimize(source)
  // After optimization, should be a single Iconst(30)
  inspect(ir.contains("Iconst(30)"), content="true")
  inspect(ir.contains("Imul"), content="false")
}

///|
/// Test: constant folding bitwise AND - 0xFF & 0x0F → 0x0F
test "egraph: const_fold_and" {
  let source =
    #|(module
    #|  (func (export "test") (result i32)
    #|    (i32.and (i32.const 255) (i32.const 15))
    #|  )
    #|)
  let ir = compile_and_optimize(source)
  // After optimization, should be Iconst(15)
  inspect(ir.contains("Iconst(15)"), content="true")
  inspect(ir.contains("Band"), content="false")
}

///|
/// Test: constant folding bitwise OR - 0xF0 | 0x0F → 0xFF
test "egraph: const_fold_or" {
  let source =
    #|(module
    #|  (func (export "test") (result i32)
    #|    (i32.or (i32.const 240) (i32.const 15))
    #|  )
    #|)
  let ir = compile_and_optimize(source)
  // After optimization, should be Iconst(255)
  inspect(ir.contains("Iconst(255)"), content="true")
  inspect(ir.contains("Bor"), content="false")
}

///|
/// Test: constant folding bitwise XOR - 0xFF ^ 0xF0 → 0x0F
test "egraph: const_fold_xor" {
  let source =
    #|(module
    #|  (func (export "test") (result i32)
    #|    (i32.xor (i32.const 255) (i32.const 240))
    #|  )
    #|)
  let ir = compile_and_optimize(source)
  // After optimization, should be Iconst(15)
  inspect(ir.contains("Iconst(15)"), content="true")
  inspect(ir.contains("Bxor"), content="false")
}

///|
/// Test: constant folding shift left - 1 << 4 → 16
test "egraph: const_fold_shl" {
  let source =
    #|(module
    #|  (func (export "test") (result i32)
    #|    (i32.shl (i32.const 1) (i32.const 4))
    #|  )
    #|)
  let ir = compile_and_optimize(source)
  // After optimization, should be Iconst(16)
  inspect(ir.contains("Iconst(16)"), content="true")
}

///|
/// Test: chained constant folding - (10 + 20) * 2 → 60
test "egraph: const_fold_chain" {
  let source =
    #|(module
    #|  (func (export "test") (result i32)
    #|    (i32.mul (i32.add (i32.const 10) (i32.const 20)) (i32.const 2))
    #|  )
    #|)
  let ir = compile_and_optimize(source)
  // After optimization, should be Iconst(60)
  inspect(ir.contains("Iconst(60)"), content="true")
  inspect(ir.contains("Iadd"), content="false")
  inspect(ir.contains("Imul"), content="false")
}

///|
/// Test: comparison constant folding - 5 < 10 → 1 (true)
test "egraph: const_fold_cmp_lt_true" {
  let source =
    #|(module
    #|  (func (export "test") (result i32)
    #|    (i32.lt_s (i32.const 5) (i32.const 10))
    #|  )
    #|)
  let ir = compile_and_optimize(source)
  // After optimization, should be Iconst(1) for true
  inspect(ir.contains("Iconst(1)"), content="true")
}

///|
/// Test: comparison constant folding - 10 < 5 → 0 (false)
test "egraph: const_fold_cmp_lt_false" {
  let source =
    #|(module
    #|  (func (export "test") (result i32)
    #|    (i32.lt_s (i32.const 10) (i32.const 5))
    #|  )
    #|)
  let ir = compile_and_optimize(source)
  // After optimization, should be Iconst(0) for false
  inspect(ir.contains("Iconst(0)"), content="true")
}

///|
/// Test: equality constant folding - 42 == 42 → 1 (true)
test "egraph: const_fold_eq_true" {
  let source =
    #|(module
    #|  (func (export "test") (result i32)
    #|    (i32.eq (i32.const 42) (i32.const 42))
    #|  )
    #|)
  let ir = compile_and_optimize(source)
  // After optimization, should be Iconst(1) for true
  inspect(ir.contains("Iconst(1)"), content="true")
}
