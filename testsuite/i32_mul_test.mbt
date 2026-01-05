///|
test "i32 mul" {
  let source =
    #|(module
    #|  (memory 1)
    #|  (func (export "test") (param i32) (result i32)
    #|    (local.get 0)
    #|    (i32.const 3)
    #|    (i32.mul)
    #|  )
    #|)
  let ir = @wat.parse(source)
  let func_code = ir.codes[0]
  let func_type_idx = ir.funcs[0]
  let func_type = ir.get_func_type(func_type_idx)

  // Get locals from the function code
  let locals : Array[@types.ValueType] = []
  for loc in func_code.locals {
    locals.push(loc)
  }

  // Create translator and translate WASM to IR
  let translator = @ir.Translator::new(
    "test",
    func_type,
    locals,
    @types.extract_func_types(ir.types),
    ir.funcs.mapi(fn(i, _) { ir.funcs[i] }),
    0, // num_imports
    [], // import_func_type_indices
  )
  let ir_func = translator.translate(func_code.body)
  inspect(
    ir_func.print(),
    content=(
      #|function test(v0:i64, v1:i64, v2:i32) -> i32 {
      #|block0:
      #|    v3:i32 = iconst 3
      #|    v4:i32 = imul v2, v3
      #|    return v4
      #|}
      #|
    ),
  )
  let vcode = @lower.lower_function(ir_func)
  inspect(
    vcode,
    content=(
      #|vcode test(v0:int, v1:int, v2:int) -> int {
      #|block0:
      #|    v3 = ldi 3
      #|    v4 = mul32 v2, v3
      #|    ret v4
      #|}
      #|
    ),
  )
  let allocated_func = @regalloc.allocate_registers_aarch64(vcode)
  inspect(
    allocated_func.print(),
    content=(
      #|vcode test(v0:int, v1:int, v2:int) -> int {
      #|block0:
      #|    x8 = ldi 3
      #|    x9 = mul32 x2, x8
      #|    ret x9
      #|}
      #|
    ),
  )
  let mc = @emit.emit_function(allocated_func)
  inspect(
    mc.dump_disasm(),
    content=(
      #|block0:
      #|  0000: 680080d2  movz x8, #3, lsl #0
      #|  0004: 497c081b  mul w9, w2, w8
      #|  0008: e00309aa  mov x0, x9
      #|  000c: c0035fd6  ret
      #|
    ),
  )
  let code_bytes = mc.get_bytes()
  let jit_module = @jit.JITModule::from_single_function(
    code_bytes,
    "test",
    [@types.ValueType::I32], // param_types
    [@types.ValueType::I32], // result_types
    4096L, // mem_size
  )
  guard jit_module is Some(jm) else { return }
  let func = jm.get_func_by_name("test")
  guard func is Some(f) else { return }
  // 4 * 3 = 12
  let @jit.Single((result0 : Int)) = jm.call_with_context_poly(
    f,
    @jit.Single(4),
  )
  assert_eq(result0, 12)
  // 7 * 3 = 21
  let @jit.Single((result1 : Int)) = jm.call_with_context_poly(
    f,
    @jit.Single(7),
  )
  assert_eq(result1, 21)
  // 0 * 3 = 0
  let @jit.Single((result2 : Int)) = jm.call_with_context_poly(
    f,
    @jit.Single(0),
  )
  assert_eq(result2, 0)
}
