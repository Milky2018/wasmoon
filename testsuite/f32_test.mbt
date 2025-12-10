///|
test "f32 add" {
  let source =
    #|(module
    #|  (memory 1)
    #|  (func (export "test") (param f32) (result f32)
    #|    (local.get 0)
    #|    (f32.const 15.5)
    #|    (f32.add)
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
      #|function test(v0:f32) -> f32 {
      #|block0:
      #|    v1:f32 = fconst 15.5
      #|    v2:f32 = fadd v0, v1
      #|    return v2
      #|}
      #|
    ),
  )
  let vcode = @vcode.lower_function(ir_func)
  inspect(
    vcode,
    content=(
      #|vcode test(f0:float) -> float {
      #|block0:
      #|    f1 = ldf 15.5
      #|    f2 = fadd f0, f1
      #|    ret f2
      #|}
      #|
    ),
  )
  let allocated_func = @vcode.allocate_registers_aarch64(vcode)
  inspect(
    allocated_func.print(),
    content=(
      #|vcode test(f0:float) -> float {
      #|block0:
      #|    d1 = ldf 15.5
      #|    d2 = fadd d0, d1
      #|    ret d2
      #|}
      #|
    ),
  )
  let mc = @vcode.emit_function(allocated_func)
  let ctx = @jit.JITContext::new(1)
  guard ctx is Some(jit_ctx) else { return }
  defer jit_ctx.free()
  let mem_size = 4096L
  let mem_ptr = @jit.alloc_memory(mem_size)
  guard mem_ptr != 0L else { return }
  defer @jit.free_memory(mem_ptr)
  jit_ctx.set_memory(mem_ptr, mem_size)
  let code_bytes = mc.get_bytes()
  let exec_code = @jit.ExecCode::new(code_bytes)
  guard exec_code is Some(exec)
  defer exec.free()
  inspect(
    jit_ctx.call_i64_i64(exec.ptr, (0).to_int64()) & 0xFFFFFFFFL,
    content="1098383360",
  )
  inspect(
    jit_ctx.call_i64_i64(exec.ptr, (1).to_int64()) & 0xFFFFFFFFL,
    content="1098383360",
  )
  inspect(
    jit_ctx.call_i64_i64(exec.ptr, (2).to_int64()) & 0xFFFFFFFFL,
    content="1098383360",
  )
}
