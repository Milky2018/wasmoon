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
  let func_type = ir.types[func_type_idx]

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
    ir.types,
    ir.funcs.mapi(fn(i, _) { ir.funcs[i] }),
    0, // num_imports
    [], // import_func_type_indices
  )
  let ir_func = translator.translate(func_code.body)
  inspect(
    ir_func.print(),
    content=(
      #|function test(v0:i32) -> i32 {
      #|block0:
      #|    v1:i32 = iconst 3
      #|    v2:i32 = imul v0, v1
      #|    return v2
      #|}
      #|
    ),
  )
  let vcode = @lower.lower_function(ir_func)
  inspect(
    vcode,
    content=(
      #|vcode test(v0:int) -> int {
      #|block0:
      #|    v1 = ldi 3
      #|    v2 = mul v0, v1
      #|    ret v2
      #|}
      #|
    ),
  )
  let allocated_func = @lower.allocate_registers_aarch64(vcode)
  inspect(
    allocated_func.print(),
    content=(
      #|vcode test(v0:int) -> int {
      #|block0:
      #|    x8 = ldi 3
      #|    x9 = mul x0, x8
      #|    ret x9
      #|}
      #|
    ),
  )
  let mc = @emit.emit_function(allocated_func)
  inspect(
    mc.dump_disasm(),
    content=(
      #|  0000: ff0301d1  sub sp, sp, #64
      #|  0004: f35300a9  stp x19, x20, [sp, #0]
      #|  0008: f55b01a9  stp x21, x22, [sp, #16]
      #|  000c: f87f02a9  stp x24, x31, [sp, #32]
      #|  0010: 740240f9  ldr x20, [x19, #0]
      #|  0014: 750a40f9  ldr x21, [x19, #16]
      #|  0018: 760e40f9  ldr x22, [x19, #24]
      #|  001c: 780640f9  ldr x24, [x19, #8]
      #|block0:
      #|  0020: 680080d2  movz x8, #3, lsl #0
      #|  0024: 097c089b  mul x9, x0, x8
      #|  0028: e00309aa  mov x0, x9
      #|  002c: f35340a9  ldp x19, x20, [sp, #0]
      #|  0030: f55b41a9  ldp x21, x22, [sp, #16]
      #|  0034: f81340f9  ldr x24, [x31, #32]
      #|  0038: ff030191  add sp, sp, #64
      #|  003c: c0035fd6  ret
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
  defer jm.free()
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
