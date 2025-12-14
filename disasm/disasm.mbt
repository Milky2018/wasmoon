// WASM Disassembler - Convert WASM binary modules to readable text format
// Outputs in WAT-like syntax for human readability

///|
/// Disassemble a WASM module to text format
pub fn disassemble(mod_ : @types.Module) -> String {
  let buf = StringBuilder::new()
  buf.write_string("(module\n")

  // Types section
  for i, func_type in mod_.types {
    buf.write_string("  (type (;")
    buf.write_string(i.to_string())
    buf.write_string(";) ")
    write_func_type(buf, func_type)
    buf.write_string(")\n")
  }

  // Imports section
  for imp in mod_.imports {
    buf.write_string("  (import \"")
    buf.write_string(imp.mod_name)
    buf.write_string("\" \"")
    buf.write_string(imp.name)
    buf.write_string("\" ")
    write_import_desc(buf, imp.desc)
    buf.write_string(")\n")
  }

  // Functions section (declarations)
  let num_func_imports = count_func_imports(mod_.imports)
  for i, type_idx in mod_.funcs {
    let func_idx = num_func_imports + i
    buf.write_string("  (func (;")
    buf.write_string(func_idx.to_string())
    buf.write_string(";) (type ")
    buf.write_string(type_idx.to_string())
    buf.write_string(")")
    // Get function type for signature
    if type_idx < mod_.types.length() {
      let func_type = mod_.types[type_idx]
      write_func_params_results(buf, func_type)
    }
    buf.write_string("\n")
    // Write function body
    if i < mod_.codes.length() {
      let code = mod_.codes[i]
      write_locals(buf, code.locals)
      write_instructions(buf, code.body, 2)
    }
    buf.write_string("  )\n")
  }

  // Tables section
  for i, table in mod_.tables {
    buf.write_string("  (table (;")
    buf.write_string(i.to_string())
    buf.write_string(";) ")
    write_limits(buf, table.type_.limits)
    buf.write_string(" ")
    write_value_type(buf, table.type_.elem_type)
    buf.write_string(")\n")
  }

  // Memories section
  for i, mem in mod_.memories {
    buf.write_string("  (memory (;")
    buf.write_string(i.to_string())
    buf.write_string(";) ")
    write_limits(buf, mem.limits)
    buf.write_string(")\n")
  }

  // Globals section
  for i, global in mod_.globals {
    buf.write_string("  (global (;")
    buf.write_string(i.to_string())
    buf.write_string(";) ")
    write_global_type(buf, global.type_)
    buf.write_string(" (")
    write_instructions_inline(buf, global.init)
    buf.write_string("))\n")
  }

  // Exports section
  for exp in mod_.exports {
    buf.write_string("  (export \"")
    buf.write_string(exp.name)
    buf.write_string("\" ")
    write_export_desc(buf, exp.desc)
    buf.write_string(")\n")
  }

  // Start section
  match mod_.start {
    Some(start_idx) => {
      buf.write_string("  (start ")
      buf.write_string(start_idx.to_string())
      buf.write_string(")\n")
    }
    None => ()
  }

  // Element segments
  for i, elem in mod_.elems {
    buf.write_string("  (elem (;")
    buf.write_string(i.to_string())
    buf.write_string(";) ")
    match elem.mode {
      @types.ElemMode::Active(table_idx, offset) => {
        buf.write_string("(table ")
        buf.write_string(table_idx.to_string())
        buf.write_string(") (")
        write_instructions_inline(buf, offset)
        buf.write_string(") func")
      }
      @types.ElemMode::Passive => buf.write_string("func")
      @types.ElemMode::Declarative => buf.write_string("declare func")
    }
    for init_expr in elem.init {
      buf.write_string(" ")
      // Extract function index from init expression
      match init_expr {
        [@types.Instruction::RefFunc(idx)] => buf.write_string(idx.to_string())
        [@types.Instruction::I32Const(idx)] => buf.write_string(idx.to_string())
        _ => buf.write_string("?")
      }
    }
    buf.write_string(")\n")
  }

  // Data segments
  for i, data in mod_.datas {
    buf.write_string("  (data (;")
    buf.write_string(i.to_string())
    buf.write_string(";) (memory ")
    buf.write_string(data.memory_idx.to_string())
    buf.write_string(") (")
    write_instructions_inline(buf, data.offset)
    buf.write_string(") \"")
    write_escaped_bytes(buf, data.init)
    buf.write_string("\")\n")
  }
  buf.write_string(")\n")
  buf.to_string()
}

///|
fn count_func_imports(imports : Array[@types.Import]) -> Int {
  let mut count = 0
  for imp in imports {
    if imp.desc is Func(_) {
      count = count + 1
    }
  }
  count
}

///|
fn write_func_type(buf : StringBuilder, ft : @types.FuncType) -> Unit {
  buf.write_string("(func")
  if ft.params.length() > 0 {
    buf.write_string(" (param")
    for p in ft.params {
      buf.write_string(" ")
      write_value_type(buf, p)
    }
    buf.write_string(")")
  }
  if ft.results.length() > 0 {
    buf.write_string(" (result")
    for r in ft.results {
      buf.write_string(" ")
      write_value_type(buf, r)
    }
    buf.write_string(")")
  }
  buf.write_string(")")
}

///|
fn write_func_params_results(buf : StringBuilder, ft : @types.FuncType) -> Unit {
  if ft.params.length() > 0 {
    buf.write_string(" (param")
    for p in ft.params {
      buf.write_string(" ")
      write_value_type(buf, p)
    }
    buf.write_string(")")
  }
  if ft.results.length() > 0 {
    buf.write_string(" (result")
    for r in ft.results {
      buf.write_string(" ")
      write_value_type(buf, r)
    }
    buf.write_string(")")
  }
}

///|
fn write_value_type(buf : StringBuilder, vt : @types.ValueType) -> Unit {
  match vt {
    I32 => buf.write_string("i32")
    I64 => buf.write_string("i64")
    F32 => buf.write_string("f32")
    F64 => buf.write_string("f64")
    V128 => buf.write_string("v128")
    FuncRef => buf.write_string("funcref")
    ExternRef => buf.write_string("externref")
    RefFunc => buf.write_string("(ref func)")
    RefExtern => buf.write_string("(ref extern)")
    RefFuncTyped(idx) => buf.write_string("(ref \{idx})")
    RefNullFuncTyped(idx) => buf.write_string("(ref null \{idx})")
  }
}

///|
fn write_limits(buf : StringBuilder, limits : @types.Limits) -> Unit {
  buf.write_string(limits.min.to_string())
  match limits.max {
    Some(max) => {
      buf.write_string(" ")
      buf.write_string(max.to_string())
    }
    None => ()
  }
}

///|
fn write_global_type(buf : StringBuilder, gt : @types.GlobalType) -> Unit {
  if gt.mutable {
    buf.write_string("(mut ")
    write_value_type(buf, gt.value_type)
    buf.write_string(")")
  } else {
    write_value_type(buf, gt.value_type)
  }
}

///|
fn write_import_desc(buf : StringBuilder, desc : @types.ImportDesc) -> Unit {
  match desc {
    Func(type_idx) => {
      buf.write_string("(func (type ")
      buf.write_string(type_idx.to_string())
      buf.write_string("))")
    }
    Table(table_type) => {
      buf.write_string("(table ")
      write_limits(buf, table_type.limits)
      buf.write_string(" ")
      write_value_type(buf, table_type.elem_type)
      buf.write_string(")")
    }
    Memory(mem_type) => {
      buf.write_string("(memory ")
      write_limits(buf, mem_type.limits)
      buf.write_string(")")
    }
    Global(global_type) => {
      buf.write_string("(global ")
      write_global_type(buf, global_type)
      buf.write_string(")")
    }
  }
}

///|
fn write_export_desc(buf : StringBuilder, desc : @types.ExportDesc) -> Unit {
  match desc {
    Func(idx) => {
      buf.write_string("(func ")
      buf.write_string(idx.to_string())
      buf.write_string(")")
    }
    Table(idx) => {
      buf.write_string("(table ")
      buf.write_string(idx.to_string())
      buf.write_string(")")
    }
    Memory(idx) => {
      buf.write_string("(memory ")
      buf.write_string(idx.to_string())
      buf.write_string(")")
    }
    Global(idx) => {
      buf.write_string("(global ")
      buf.write_string(idx.to_string())
      buf.write_string(")")
    }
  }
}

///|
fn write_locals(buf : StringBuilder, locals : Array[@types.ValueType]) -> Unit {
  if locals.length() == 0 {
    return
  }
  // Group consecutive locals of the same type
  let mut i = 0
  while i < locals.length() {
    let ty = locals[i]
    let mut count = 1
    while i + count < locals.length() && locals[i + count] == ty {
      count = count + 1
    }
    buf.write_string("    (local")
    for _ in 0..<count {
      buf.write_string(" ")
      write_value_type(buf, ty)
    }
    buf.write_string(")\n")
    i = i + count
  }
}

///|
fn write_instructions(
  buf : StringBuilder,
  instrs : Array[@types.Instruction],
  indent : Int,
) -> Unit {
  for instr in instrs {
    write_indent(buf, indent)
    write_instruction(buf, instr, indent)
    buf.write_string("\n")
  }
}

///|
fn write_instructions_inline(
  buf : StringBuilder,
  instrs : Array[@types.Instruction],
) -> Unit {
  for i, instr in instrs {
    if i > 0 {
      buf.write_string(" ")
    }
    write_instruction_simple(buf, instr)
  }
}

///|
fn write_indent(buf : StringBuilder, indent : Int) -> Unit {
  for _ in 0..<indent {
    buf.write_string("  ")
  }
}

///|
fn write_instruction(
  buf : StringBuilder,
  instr : @types.Instruction,
  indent : Int,
) -> Unit {
  match instr {
    // Control instructions with nested blocks
    Block(bt, body) => {
      buf.write_string("block")
      write_block_type(buf, bt)
      buf.write_string("\n")
      write_instructions(buf, body, indent + 1)
      write_indent(buf, indent)
      buf.write_string("end")
    }
    Loop(bt, body) => {
      buf.write_string("loop")
      write_block_type(buf, bt)
      buf.write_string("\n")
      write_instructions(buf, body, indent + 1)
      write_indent(buf, indent)
      buf.write_string("end")
    }
    If(bt, then_body, else_body) => {
      buf.write_string("if")
      write_block_type(buf, bt)
      buf.write_string("\n")
      write_instructions(buf, then_body, indent + 1)
      if else_body.length() > 0 {
        write_indent(buf, indent)
        buf.write_string("else\n")
        write_instructions(buf, else_body, indent + 1)
      }
      write_indent(buf, indent)
      buf.write_string("end")
    }
    _ => write_instruction_simple(buf, instr)
  }
}

///|
fn write_block_type(buf : StringBuilder, bt : @types.BlockType) -> Unit {
  if bt is Empty {
    ()
  } else if bt is Value(vt) {
    buf.write_string(" (result ")
    write_value_type(buf, vt)
    buf.write_string(")")
  } else if bt is MultiValue(vts) {
    buf.write_string(" (result")
    for vt in vts {
      buf.write_string(" ")
      write_value_type(buf, vt)
    }
    buf.write_string(")")
  } else if bt is InlineType(params, results) {
    if params.length() > 0 {
      buf.write_string(" (param")
      for vt in params {
        buf.write_string(" ")
        write_value_type(buf, vt)
      }
      buf.write_string(")")
    }
    if results.length() > 0 {
      buf.write_string(" (result")
      for vt in results {
        buf.write_string(" ")
        write_value_type(buf, vt)
      }
      buf.write_string(")")
    }
  } else if bt is TypeIndex(idx) {
    buf.write_string(" (type ")
    buf.write_string(idx.to_string())
    buf.write_string(")")
  }
}

///|
fn write_instruction_simple(
  buf : StringBuilder,
  instr : @types.Instruction,
) -> Unit {
  match instr {
    // Control instructions
    Unreachable => buf.write_string("unreachable")
    Nop => buf.write_string("nop")
    Br(idx) => {
      buf.write_string("br ")
      buf.write_string(idx.to_string())
    }
    BrIf(idx) => {
      buf.write_string("br_if ")
      buf.write_string(idx.to_string())
    }
    BrTable(labels, default) => {
      buf.write_string("br_table")
      for l in labels {
        buf.write_string(" ")
        buf.write_string(l.to_string())
      }
      buf.write_string(" ")
      buf.write_string(default.to_string())
    }
    Return => buf.write_string("return")
    Call(idx) => {
      buf.write_string("call ")
      buf.write_string(idx.to_string())
    }
    CallIndirect(type_idx, table_idx) => {
      buf.write_string("call_indirect (type ")
      buf.write_string(type_idx.to_string())
      buf.write_string(")")
      if table_idx != 0 {
        buf.write_string(" (table ")
        buf.write_string(table_idx.to_string())
        buf.write_string(")")
      }
    }
    CallRef(type_idx) => {
      buf.write_string("call_ref ")
      buf.write_string(type_idx.to_string())
    }

    // Parametric instructions
    Drop => buf.write_string("drop")
    Select => buf.write_string("select")

    // Variable instructions
    LocalGet(idx) => {
      buf.write_string("local.get ")
      buf.write_string(idx.to_string())
    }
    LocalSet(idx) => {
      buf.write_string("local.set ")
      buf.write_string(idx.to_string())
    }
    LocalTee(idx) => {
      buf.write_string("local.tee ")
      buf.write_string(idx.to_string())
    }
    GlobalGet(idx) => {
      buf.write_string("global.get ")
      buf.write_string(idx.to_string())
    }
    GlobalSet(idx) => {
      buf.write_string("global.set ")
      buf.write_string(idx.to_string())
    }

    // Table instructions
    TableGet(idx) => {
      buf.write_string("table.get ")
      buf.write_string(idx.to_string())
    }
    TableSet(idx) => {
      buf.write_string("table.set ")
      buf.write_string(idx.to_string())
    }
    TableSize(idx) => {
      buf.write_string("table.size ")
      buf.write_string(idx.to_string())
    }
    TableGrow(idx) => {
      buf.write_string("table.grow ")
      buf.write_string(idx.to_string())
    }
    TableFill(idx) => {
      buf.write_string("table.fill ")
      buf.write_string(idx.to_string())
    }
    TableCopy(dst, src) => {
      buf.write_string("table.copy ")
      buf.write_string(dst.to_string())
      buf.write_string(" ")
      buf.write_string(src.to_string())
    }
    TableInit(table_idx, elem_idx) => {
      buf.write_string("table.init ")
      buf.write_string(table_idx.to_string())
      buf.write_string(" ")
      buf.write_string(elem_idx.to_string())
    }

    // Memory load instructions
    I32Load(align, offset) => write_mem_instr(buf, "i32.load", align, offset)
    I64Load(align, offset) => write_mem_instr(buf, "i64.load", align, offset)
    F32Load(align, offset) => write_mem_instr(buf, "f32.load", align, offset)
    F64Load(align, offset) => write_mem_instr(buf, "f64.load", align, offset)
    I32Load8S(align, offset) =>
      write_mem_instr(buf, "i32.load8_s", align, offset)
    I32Load8U(align, offset) =>
      write_mem_instr(buf, "i32.load8_u", align, offset)
    I32Load16S(align, offset) =>
      write_mem_instr(buf, "i32.load16_s", align, offset)
    I32Load16U(align, offset) =>
      write_mem_instr(buf, "i32.load16_u", align, offset)
    I64Load8S(align, offset) =>
      write_mem_instr(buf, "i64.load8_s", align, offset)
    I64Load8U(align, offset) =>
      write_mem_instr(buf, "i64.load8_u", align, offset)
    I64Load16S(align, offset) =>
      write_mem_instr(buf, "i64.load16_s", align, offset)
    I64Load16U(align, offset) =>
      write_mem_instr(buf, "i64.load16_u", align, offset)
    I64Load32S(align, offset) =>
      write_mem_instr(buf, "i64.load32_s", align, offset)
    I64Load32U(align, offset) =>
      write_mem_instr(buf, "i64.load32_u", align, offset)

    // Memory store instructions
    I32Store(align, offset) => write_mem_instr(buf, "i32.store", align, offset)
    I64Store(align, offset) => write_mem_instr(buf, "i64.store", align, offset)
    F32Store(align, offset) => write_mem_instr(buf, "f32.store", align, offset)
    F64Store(align, offset) => write_mem_instr(buf, "f64.store", align, offset)
    I32Store8(align, offset) =>
      write_mem_instr(buf, "i32.store8", align, offset)
    I32Store16(align, offset) =>
      write_mem_instr(buf, "i32.store16", align, offset)
    I64Store8(align, offset) =>
      write_mem_instr(buf, "i64.store8", align, offset)
    I64Store16(align, offset) =>
      write_mem_instr(buf, "i64.store16", align, offset)
    I64Store32(align, offset) =>
      write_mem_instr(buf, "i64.store32", align, offset)

    // Memory misc
    MemorySize => buf.write_string("memory.size")
    MemoryGrow => buf.write_string("memory.grow")
    MemoryInit(idx) => {
      buf.write_string("memory.init ")
      buf.write_string(idx.to_string())
    }
    DataDrop(idx) => {
      buf.write_string("data.drop ")
      buf.write_string(idx.to_string())
    }
    MemoryCopy => buf.write_string("memory.copy")
    MemoryFill => buf.write_string("memory.fill")
    ElemDrop(idx) => {
      buf.write_string("elem.drop ")
      buf.write_string(idx.to_string())
    }

    // Reference instructions
    RefNull(vt) => {
      buf.write_string("ref.null ")
      write_value_type(buf, vt)
    }
    RefIsNull => buf.write_string("ref.is_null")
    RefFunc(idx) => {
      buf.write_string("ref.func ")
      buf.write_string(idx.to_string())
    }
    RefAsNonNull => buf.write_string("ref.as_non_null")
    BrOnNull(idx) => {
      buf.write_string("br_on_null ")
      buf.write_string(idx.to_string())
    }

    // Constants
    I32Const(v) => {
      buf.write_string("i32.const ")
      buf.write_string(v.to_string())
    }
    I64Const(v) => {
      buf.write_string("i64.const ")
      buf.write_string(v.to_string())
    }
    F32Const(v) => {
      buf.write_string("f32.const ")
      write_f32(buf, v)
    }
    F64Const(v) => {
      buf.write_string("f64.const ")
      write_f64(buf, v)
    }

    // i32 operations
    I32Eqz => buf.write_string("i32.eqz")
    I32Eq => buf.write_string("i32.eq")
    I32Ne => buf.write_string("i32.ne")
    I32LtS => buf.write_string("i32.lt_s")
    I32LtU => buf.write_string("i32.lt_u")
    I32GtS => buf.write_string("i32.gt_s")
    I32GtU => buf.write_string("i32.gt_u")
    I32LeS => buf.write_string("i32.le_s")
    I32LeU => buf.write_string("i32.le_u")
    I32GeS => buf.write_string("i32.ge_s")
    I32GeU => buf.write_string("i32.ge_u")
    I32Clz => buf.write_string("i32.clz")
    I32Ctz => buf.write_string("i32.ctz")
    I32Popcnt => buf.write_string("i32.popcnt")
    I32Add => buf.write_string("i32.add")
    I32Sub => buf.write_string("i32.sub")
    I32Mul => buf.write_string("i32.mul")
    I32DivS => buf.write_string("i32.div_s")
    I32DivU => buf.write_string("i32.div_u")
    I32RemS => buf.write_string("i32.rem_s")
    I32RemU => buf.write_string("i32.rem_u")
    I32And => buf.write_string("i32.and")
    I32Or => buf.write_string("i32.or")
    I32Xor => buf.write_string("i32.xor")
    I32Shl => buf.write_string("i32.shl")
    I32ShrS => buf.write_string("i32.shr_s")
    I32ShrU => buf.write_string("i32.shr_u")
    I32Rotl => buf.write_string("i32.rotl")
    I32Rotr => buf.write_string("i32.rotr")
    I32Extend8S => buf.write_string("i32.extend8_s")
    I32Extend16S => buf.write_string("i32.extend16_s")

    // i64 operations
    I64Eqz => buf.write_string("i64.eqz")
    I64Eq => buf.write_string("i64.eq")
    I64Ne => buf.write_string("i64.ne")
    I64LtS => buf.write_string("i64.lt_s")
    I64LtU => buf.write_string("i64.lt_u")
    I64GtS => buf.write_string("i64.gt_s")
    I64GtU => buf.write_string("i64.gt_u")
    I64LeS => buf.write_string("i64.le_s")
    I64LeU => buf.write_string("i64.le_u")
    I64GeS => buf.write_string("i64.ge_s")
    I64GeU => buf.write_string("i64.ge_u")
    I64Clz => buf.write_string("i64.clz")
    I64Ctz => buf.write_string("i64.ctz")
    I64Popcnt => buf.write_string("i64.popcnt")
    I64Add => buf.write_string("i64.add")
    I64Sub => buf.write_string("i64.sub")
    I64Mul => buf.write_string("i64.mul")
    I64DivS => buf.write_string("i64.div_s")
    I64DivU => buf.write_string("i64.div_u")
    I64RemS => buf.write_string("i64.rem_s")
    I64RemU => buf.write_string("i64.rem_u")
    I64And => buf.write_string("i64.and")
    I64Or => buf.write_string("i64.or")
    I64Xor => buf.write_string("i64.xor")
    I64Shl => buf.write_string("i64.shl")
    I64ShrS => buf.write_string("i64.shr_s")
    I64ShrU => buf.write_string("i64.shr_u")
    I64Rotl => buf.write_string("i64.rotl")
    I64Rotr => buf.write_string("i64.rotr")
    I64Extend8S => buf.write_string("i64.extend8_s")
    I64Extend16S => buf.write_string("i64.extend16_s")
    I64Extend32S => buf.write_string("i64.extend32_s")

    // f32 operations
    F32Eq => buf.write_string("f32.eq")
    F32Ne => buf.write_string("f32.ne")
    F32Lt => buf.write_string("f32.lt")
    F32Gt => buf.write_string("f32.gt")
    F32Le => buf.write_string("f32.le")
    F32Ge => buf.write_string("f32.ge")
    F32Abs => buf.write_string("f32.abs")
    F32Neg => buf.write_string("f32.neg")
    F32Ceil => buf.write_string("f32.ceil")
    F32Floor => buf.write_string("f32.floor")
    F32Trunc => buf.write_string("f32.trunc")
    F32Nearest => buf.write_string("f32.nearest")
    F32Sqrt => buf.write_string("f32.sqrt")
    F32Add => buf.write_string("f32.add")
    F32Sub => buf.write_string("f32.sub")
    F32Mul => buf.write_string("f32.mul")
    F32Div => buf.write_string("f32.div")
    F32Min => buf.write_string("f32.min")
    F32Max => buf.write_string("f32.max")
    F32Copysign => buf.write_string("f32.copysign")

    // f64 operations
    F64Eq => buf.write_string("f64.eq")
    F64Ne => buf.write_string("f64.ne")
    F64Lt => buf.write_string("f64.lt")
    F64Gt => buf.write_string("f64.gt")
    F64Le => buf.write_string("f64.le")
    F64Ge => buf.write_string("f64.ge")
    F64Abs => buf.write_string("f64.abs")
    F64Neg => buf.write_string("f64.neg")
    F64Ceil => buf.write_string("f64.ceil")
    F64Floor => buf.write_string("f64.floor")
    F64Trunc => buf.write_string("f64.trunc")
    F64Nearest => buf.write_string("f64.nearest")
    F64Sqrt => buf.write_string("f64.sqrt")
    F64Add => buf.write_string("f64.add")
    F64Sub => buf.write_string("f64.sub")
    F64Mul => buf.write_string("f64.mul")
    F64Div => buf.write_string("f64.div")
    F64Min => buf.write_string("f64.min")
    F64Max => buf.write_string("f64.max")
    F64Copysign => buf.write_string("f64.copysign")

    // Conversion instructions
    I32WrapI64 => buf.write_string("i32.wrap_i64")
    I32TruncF32S => buf.write_string("i32.trunc_f32_s")
    I32TruncF32U => buf.write_string("i32.trunc_f32_u")
    I32TruncF64S => buf.write_string("i32.trunc_f64_s")
    I32TruncF64U => buf.write_string("i32.trunc_f64_u")
    I64ExtendI32S => buf.write_string("i64.extend_i32_s")
    I64ExtendI32U => buf.write_string("i64.extend_i32_u")
    I64TruncF32S => buf.write_string("i64.trunc_f32_s")
    I64TruncF32U => buf.write_string("i64.trunc_f32_u")
    I64TruncF64S => buf.write_string("i64.trunc_f64_s")
    I64TruncF64U => buf.write_string("i64.trunc_f64_u")
    F32ConvertI32S => buf.write_string("f32.convert_i32_s")
    F32ConvertI32U => buf.write_string("f32.convert_i32_u")
    F32ConvertI64S => buf.write_string("f32.convert_i64_s")
    F32ConvertI64U => buf.write_string("f32.convert_i64_u")
    F32DemoteF64 => buf.write_string("f32.demote_f64")
    F64ConvertI32S => buf.write_string("f64.convert_i32_s")
    F64ConvertI32U => buf.write_string("f64.convert_i32_u")
    F64ConvertI64S => buf.write_string("f64.convert_i64_s")
    F64ConvertI64U => buf.write_string("f64.convert_i64_u")
    F64PromoteF32 => buf.write_string("f64.promote_f32")
    I32ReinterpretF32 => buf.write_string("i32.reinterpret_f32")
    I64ReinterpretF64 => buf.write_string("i64.reinterpret_f64")
    F32ReinterpretI32 => buf.write_string("f32.reinterpret_i32")
    F64ReinterpretI64 => buf.write_string("f64.reinterpret_i64")

    // Saturating truncation
    I32TruncSatF32S => buf.write_string("i32.trunc_sat_f32_s")
    I32TruncSatF32U => buf.write_string("i32.trunc_sat_f32_u")
    I32TruncSatF64S => buf.write_string("i32.trunc_sat_f64_s")
    I32TruncSatF64U => buf.write_string("i32.trunc_sat_f64_u")
    I64TruncSatF32S => buf.write_string("i64.trunc_sat_f32_s")
    I64TruncSatF32U => buf.write_string("i64.trunc_sat_f32_u")
    I64TruncSatF64S => buf.write_string("i64.trunc_sat_f64_s")
    I64TruncSatF64U => buf.write_string("i64.trunc_sat_f64_u")

    // Nested blocks - should be handled by write_instruction
    Block(_, _) | Loop(_, _) | If(_, _, _) =>
      buf.write_string(";; nested block")
  }
}

///|
fn write_mem_instr(
  buf : StringBuilder,
  name : String,
  align : Int,
  offset : Int,
) -> Unit {
  buf.write_string(name)
  if offset != 0 {
    buf.write_string(" offset=")
    buf.write_string(offset.to_string())
  }
  if align != 0 {
    buf.write_string(" align=")
    buf.write_string((1 << align).to_string())
  }
}

///|
fn write_f32(buf : StringBuilder, v : Float) -> Unit {
  if v.is_nan() {
    buf.write_string("nan")
  } else if v.is_inf() {
    if v > (0.0 : Float) {
      buf.write_string("inf")
    } else {
      buf.write_string("-inf")
    }
  } else {
    buf.write_string(v.to_string())
  }
}

///|
fn write_f64(buf : StringBuilder, v : Double) -> Unit {
  if v.is_nan() {
    buf.write_string("nan")
  } else if v.is_inf() {
    if v > 0.0 {
      buf.write_string("inf")
    } else {
      buf.write_string("-inf")
    }
  } else {
    buf.write_string(v.to_string())
  }
}

///|
fn write_escaped_bytes(buf : StringBuilder, bytes : Bytes) -> Unit {
  for b in bytes {
    let i = b.to_int()
    if i >= 32 && i < 127 && i != 34 && i != 92 {
      // Printable ASCII (excluding " and \)
      buf.write_string(b.to_char().to_string())
    } else {
      // Escape as hex
      buf.write_string("\\")
      buf.write_string(hex_digit(i >> 4))
      buf.write_string(hex_digit(i & 0xF))
    }
  }
}

///|
fn hex_digit(n : Int) -> String {
  match n {
    0 => "0"
    1 => "1"
    2 => "2"
    3 => "3"
    4 => "4"
    5 => "5"
    6 => "6"
    7 => "7"
    8 => "8"
    9 => "9"
    10 => "a"
    11 => "b"
    12 => "c"
    13 => "d"
    14 => "e"
    15 => "f"
    _ => "?"
  }
}
