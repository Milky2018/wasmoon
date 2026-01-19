///|
fn compile_single_func_disasm(source : String) -> String {
  let m = @wat.parse(source) catch { _ => abort("parse failed") }
  let func_code = m.codes[0]
  let func_type_idx = m.funcs[0]
  let func_type = m.get_func_type(func_type_idx)
  let locals : Array[@types.ValueType] = []
  for loc in func_code.locals {
    locals.push(loc)
  }
  let translator = @ir.Translator::new(
    "test",
    func_type,
    locals,
    @types.extract_func_types(m.types),
    m.funcs.mapi(fn(i, _) { m.funcs[i] }),
    0,
    [],
  )
  let ir_func = translator.translate(func_code.body)
  @ir.optimize(ir_func) |> ignore
  let vcode = @lower.lower_function(ir_func)
  let allocated_func = @regalloc.allocate_registers_backtracking(vcode)
  let mc = @emit.emit_function(allocated_func)
  mc.dump_disasm()
}

///|
test "codegen: i32 select uses csel w" {
  let source =
    #|(module
    #|  (func (export "test") (param i32 i32 i32) (result i32)
    #|    (select (local.get 0) (local.get 1) (local.get 2))
    #|  )
    #|)
  let disasm = compile_single_func_disasm(source)
  inspect(disasm.contains("csel w"), content="true")
  inspect(!disasm.contains("csel x"), content="true")
}

///|
test "codegen: i32 select_cmp uses csel w" {
  let source =
    #|(module
    #|  (func (export "test") (param i32 i32 i32) (result i32)
    #|    (select
    #|      (local.get 0)
    #|      (local.get 1)
    #|      (i32.eq (local.get 2) (i32.const 0))
    #|    )
    #|  )
    #|)
  let disasm = compile_single_func_disasm(source)
  inspect(disasm.contains("csel w"), content="true")
  inspect(!disasm.contains("csel x"), content="true")
}

///|
test "codegen: i32.load8_s uses ldrsb w" {
  let source =
    #|(module
    #|  (memory 1)
    #|  (data (i32.const 0) "\80")
    #|  (func (export "test") (result i32)
    #|    (i32.load8_s (i32.const 0))
    #|  )
    #|)
  let disasm = compile_single_func_disasm(source)
  inspect(disasm.contains("ldrsb w"), content="true")
  inspect(!disasm.contains("ldrsb x"), content="true")
}

///|
test "codegen: i32.or uses orr w" {
  let source =
    #|(module
    #|  (func (export "test") (param i32 i32) (result i32)
    #|    (i32.or (local.get 0) (local.get 1))
    #|  )
    #|)
  let disasm = compile_single_func_disasm(source)
  inspect(disasm.contains("orr w"), content="true")
  inspect(!disasm.contains("orr x"), content="true")
}
