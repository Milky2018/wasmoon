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
  let vcode = @vcode.lower_function(ir_func)
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
  let allocated_func = @vcode.allocate_registers_aarch64(vcode)
  inspect(
    allocated_func.print(),
    content=(
      #|vcode test(v0:int) -> int {
      #|block0:
      #|    x8 = ldi 3
      #|    x19 = mul x3, x8
      #|    ret x19
      #|}
      #|
    ),
  )
  let mc = @vcode.emit_function(allocated_func)
  inspect(
    mc.dump_disasm(),
    content=(
      #|  0000: ff8300d1  sub sp, sp, #32
      #|  0004: f45700a9  stp x20, x21, [sp, #0]
      #|  0008: f64f01a9  stp x22, x19, [sp, #16]
      #|  000c: f40300aa  mov x20, x0
      #|  0010: f50301aa  mov x21, x1
      #|  0014: f60302aa  mov x22, x2
      #|block0:
      #|  0018: 680080d2  movz x8, #3, lsl #0
      #|  001c: 737c409b  mul x19, x3, x8
      #|  0020: e00313aa  mov x0, x19
      #|  0024: f45740a9  ldp x20, x21, [sp, #0]
      #|  0028: f64f41a9  ldp x22, x19, [sp, #16]
      #|  002c: ff830091  add sp, sp, #32
      #|  0030: c0035fd6  ret
      #|
    ),
  )
  let code_bytes = mc.get_bytes()
  let jit_module = @jit.JITModule::from_single_function(
    code_bytes,
    "test",
    1, // num_params
    [@types.ValueType::I32], // result_types
    4096L, // mem_size
  )
  guard jit_module is Some(jm) else { return }
  defer jm.free()
  let func = jm.get_func_by_name("test")
  guard func is Some(f) else { return }
  // 4 * 3 = 12
  let result0 = jm.call_with_context(f, [4L])
  inspect(result0[0], content="0")
  // 7 * 3 = 21
  let result1 = jm.call_with_context(f, [7L])
  inspect(result1[0], content="0")
  // 0 * 3 = 0
  let result2 = jm.call_with_context(f, [0L])
  inspect(result2[0], content="0")
}
