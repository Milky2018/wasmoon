// WASM Disassembler - Convert WASM binary modules to readable text format
// Outputs in WAT-like syntax for human readability

///|
/// Disassemble a WASM module to text format
pub fn disassemble(mod_ : @types.Module) -> String {
  let buf = StringBuilder::new()
  buf.write_string("(module\n")

  // Types section
  for i, subtype in mod_.types {
    buf.write_string("  (type (;")
    buf.write_string(i.to_string())
    buf.write_string(";) ")
    write_composite_type(buf, subtype)
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
      match mod_.types[type_idx].composite {
        Func(func_type) => write_func_params_results(buf, func_type)
        _ => ()
      }
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
  if mod_.start is Some(start_idx) {
    buf.write_string("  (start ")
    buf.write_string(start_idx.to_string())
    buf.write_string(")\n")
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
fn write_composite_type(buf : StringBuilder, st : @types.SubType) -> Unit {
  // Handle subtype wrapper
  if not(st.final_) || st.supertypes.length() > 0 {
    buf.write_string("(sub ")
    if not(st.final_) {
      buf.write_string("open ")
    }
    for sup in st.supertypes {
      buf.write_string(sup.to_string())
      buf.write_string(" ")
    }
  }
  match st.composite {
    Func(ft) => write_func_type_inner(buf, ft)
    Struct(st) => write_struct_type(buf, st)
    Array(at) => write_array_type(buf, at)
  }
  if not(st.final_) || st.supertypes.length() > 0 {
    buf.write_string(")")
  }
}

///|
fn write_func_type_inner(buf : StringBuilder, ft : @types.FuncType) -> Unit {
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
fn write_struct_type(buf : StringBuilder, st : @types.StructType) -> Unit {
  buf.write_string("(struct")
  for field in st.fields {
    buf.write_string(" (field ")
    if field.mutable {
      buf.write_string("(mut ")
    }
    write_storage_type(buf, field.storage_type)
    if field.mutable {
      buf.write_string(")")
    }
    buf.write_string(")")
  }
  buf.write_string(")")
}

///|
fn write_array_type(buf : StringBuilder, at : @types.ArrayType) -> Unit {
  buf.write_string("(array ")
  if at.element.mutable {
    buf.write_string("(mut ")
  }
  write_storage_type(buf, at.element.storage_type)
  if at.element.mutable {
    buf.write_string(")")
  }
  buf.write_string(")")
}

///|
fn write_storage_type(buf : StringBuilder, st : @types.StorageType) -> Unit {
  match st {
    Val(vt) => write_value_type(buf, vt)
    Packed(I8) => buf.write_string("i8")
    Packed(I16) => buf.write_string("i16")
  }
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
    AnyRef => buf.write_string("anyref")
    ExnRef => buf.write_string("exnref")
    NullRef => buf.write_string("nullref")
    NullFuncRef => buf.write_string("nullfuncref")
    NullExnRef => buf.write_string("nullexnref")
    NullExternRef => buf.write_string("nullexternref")
    // GC types
    StructRef => buf.write_string("structref")
    ArrayRef => buf.write_string("arrayref")
    RefStruct(idx) => buf.write_string("(ref \{idx})")
    RefNullStruct(idx) => buf.write_string("(ref null \{idx})")
    RefArray(idx) => buf.write_string("(ref \{idx})")
    RefNullArray(idx) => buf.write_string("(ref null \{idx})")
    RefAny => buf.write_string("(ref any)")
    RefEq => buf.write_string("(ref eq)")
    RefNullEq => buf.write_string("eqref")
    RefI31 => buf.write_string("(ref i31)")
    RefNullI31 => buf.write_string("i31ref")
    RefStructAbs => buf.write_string("(ref struct)")
    RefArrayAbs => buf.write_string("(ref array)")
    RefNone => buf.write_string("(ref none)")
  }
}

///|
fn write_limits(buf : StringBuilder, limits : @types.Limits) -> Unit {
  buf.write_string(limits.min.to_string())
  if limits.max is Some(max) {
    buf.write_string(" ")
    buf.write_string(max.to_string())
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
    Tag(type_idx) => {
      buf.write_string("(tag (type ")
      buf.write_string(type_idx.to_string())
      buf.write_string("))")
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
    Tag(idx) => {
      buf.write_string("(tag ")
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
    ReturnCall(idx) => {
      buf.write_string("return_call ")
      buf.write_string(idx.to_string())
    }
    ReturnCallIndirect(type_idx, table_idx) => {
      buf.write_string("return_call_indirect (type ")
      buf.write_string(type_idx.to_string())
      buf.write_string(")")
      if table_idx != 0 {
        buf.write_string(" (table ")
        buf.write_string(table_idx.to_string())
        buf.write_string(")")
      }
    }
    ReturnCallRef(type_idx) => {
      buf.write_string("return_call_ref ")
      buf.write_string(type_idx.to_string())
    }

    // Parametric instructions
    Drop => buf.write_string("drop")
    Select => buf.write_string("select")
    SelectTyped(types) => {
      buf.write_string("select")
      for ty in types {
        buf.write_string(" (result ")
        write_value_type(buf, ty)
        buf.write_string(")")
      }
    }

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
    I32Load(memidx, align, offset) =>
      write_mem_instr(buf, "i32.load", memidx, align, offset)
    I64Load(memidx, align, offset) =>
      write_mem_instr(buf, "i64.load", memidx, align, offset)
    F32Load(memidx, align, offset) =>
      write_mem_instr(buf, "f32.load", memidx, align, offset)
    F64Load(memidx, align, offset) =>
      write_mem_instr(buf, "f64.load", memidx, align, offset)
    I32Load8S(memidx, align, offset) =>
      write_mem_instr(buf, "i32.load8_s", memidx, align, offset)
    I32Load8U(memidx, align, offset) =>
      write_mem_instr(buf, "i32.load8_u", memidx, align, offset)
    I32Load16S(memidx, align, offset) =>
      write_mem_instr(buf, "i32.load16_s", memidx, align, offset)
    I32Load16U(memidx, align, offset) =>
      write_mem_instr(buf, "i32.load16_u", memidx, align, offset)
    I64Load8S(memidx, align, offset) =>
      write_mem_instr(buf, "i64.load8_s", memidx, align, offset)
    I64Load8U(memidx, align, offset) =>
      write_mem_instr(buf, "i64.load8_u", memidx, align, offset)
    I64Load16S(memidx, align, offset) =>
      write_mem_instr(buf, "i64.load16_s", memidx, align, offset)
    I64Load16U(memidx, align, offset) =>
      write_mem_instr(buf, "i64.load16_u", memidx, align, offset)
    I64Load32S(memidx, align, offset) =>
      write_mem_instr(buf, "i64.load32_s", memidx, align, offset)
    I64Load32U(memidx, align, offset) =>
      write_mem_instr(buf, "i64.load32_u", memidx, align, offset)

    // Memory store instructions
    I32Store(memidx, align, offset) =>
      write_mem_instr(buf, "i32.store", memidx, align, offset)
    I64Store(memidx, align, offset) =>
      write_mem_instr(buf, "i64.store", memidx, align, offset)
    F32Store(memidx, align, offset) =>
      write_mem_instr(buf, "f32.store", memidx, align, offset)
    F64Store(memidx, align, offset) =>
      write_mem_instr(buf, "f64.store", memidx, align, offset)
    I32Store8(memidx, align, offset) =>
      write_mem_instr(buf, "i32.store8", memidx, align, offset)
    I32Store16(memidx, align, offset) =>
      write_mem_instr(buf, "i32.store16", memidx, align, offset)
    I64Store8(memidx, align, offset) =>
      write_mem_instr(buf, "i64.store8", memidx, align, offset)
    I64Store16(memidx, align, offset) =>
      write_mem_instr(buf, "i64.store16", memidx, align, offset)
    I64Store32(memidx, align, offset) =>
      write_mem_instr(buf, "i64.store32", memidx, align, offset)

    // Memory misc
    MemorySize(memidx) => {
      buf.write_string("memory.size")
      if memidx != 0 {
        buf.write_string(" \{memidx}")
      }
    }
    MemoryGrow(memidx) => {
      buf.write_string("memory.grow")
      if memidx != 0 {
        buf.write_string(" \{memidx}")
      }
    }
    MemoryInit(memidx, dataidx) => {
      buf.write_string("memory.init")
      if memidx != 0 {
        buf.write_string(" \{memidx}")
      }
      buf.write_string(" \{dataidx}")
    }
    DataDrop(idx) => {
      buf.write_string("data.drop ")
      buf.write_string(idx.to_string())
    }
    MemoryCopy(dst, src) => {
      buf.write_string("memory.copy")
      if dst != 0 || src != 0 {
        buf.write_string(" \{dst} \{src}")
      }
    }
    MemoryFill(memidx) => {
      buf.write_string("memory.fill")
      if memidx != 0 {
        buf.write_string(" \{memidx}")
      }
    }
    ElemDrop(idx) => {
      buf.write_string("elem.drop ")
      buf.write_string(idx.to_string())
    }
    Atomic(subop, memidx, align, offset) => {
      buf.write_string("atomic.")
      buf.write_string(subop.to_string())
      buf.write_string(" (mem ")
      buf.write_string(memidx.to_string())
      buf.write_string(" align=")
      buf.write_string(align.to_string())
      buf.write_string(" offset=")
      buf.write_string(offset.to_string())
      buf.write_string(")")
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
    RefEqInstr => buf.write_string("ref.eq")
    BrOnNull(idx) => {
      buf.write_string("br_on_null ")
      buf.write_string(idx.to_string())
    }
    BrOnNonNull(idx) => {
      buf.write_string("br_on_non_null ")
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
    I64MulWideS => buf.write_string("i64.mul_wide_s")
    I64MulWideU => buf.write_string("i64.mul_wide_u")
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

    // Exception handling instructions
    Throw(tag_idx) => {
      buf.write_string("throw ")
      buf.write_string(tag_idx.to_string())
    }
    ThrowRef => buf.write_string("throw_ref")
    TryTable(_, _, _) => buf.write_string(";; try_table")

    // Nested blocks - should be handled by write_instruction
    Block(_, _) | Loop(_, _) | If(_, _, _) =>
      buf.write_string(";; nested block")

    // GC instructions - struct operations
    StructNew(type_idx) => {
      buf.write_string("struct.new ")
      buf.write_string(type_idx.to_string())
    }
    StructNewDefault(type_idx) => {
      buf.write_string("struct.new_default ")
      buf.write_string(type_idx.to_string())
    }
    StructGet(type_idx, field_idx) => {
      buf.write_string("struct.get ")
      buf.write_string(type_idx.to_string())
      buf.write_string(" ")
      buf.write_string(field_idx.to_string())
    }
    StructGetS(type_idx, field_idx) => {
      buf.write_string("struct.get_s ")
      buf.write_string(type_idx.to_string())
      buf.write_string(" ")
      buf.write_string(field_idx.to_string())
    }
    StructGetU(type_idx, field_idx) => {
      buf.write_string("struct.get_u ")
      buf.write_string(type_idx.to_string())
      buf.write_string(" ")
      buf.write_string(field_idx.to_string())
    }
    StructSet(type_idx, field_idx) => {
      buf.write_string("struct.set ")
      buf.write_string(type_idx.to_string())
      buf.write_string(" ")
      buf.write_string(field_idx.to_string())
    }

    // GC instructions - array operations
    ArrayNew(type_idx) => {
      buf.write_string("array.new ")
      buf.write_string(type_idx.to_string())
    }
    ArrayNewDefault(type_idx) => {
      buf.write_string("array.new_default ")
      buf.write_string(type_idx.to_string())
    }
    ArrayNewFixed(type_idx, len) => {
      buf.write_string("array.new_fixed ")
      buf.write_string(type_idx.to_string())
      buf.write_string(" ")
      buf.write_string(len.to_string())
    }
    ArrayNewData(type_idx, data_idx) => {
      buf.write_string("array.new_data ")
      buf.write_string(type_idx.to_string())
      buf.write_string(" ")
      buf.write_string(data_idx.to_string())
    }
    ArrayNewElem(type_idx, elem_idx) => {
      buf.write_string("array.new_elem ")
      buf.write_string(type_idx.to_string())
      buf.write_string(" ")
      buf.write_string(elem_idx.to_string())
    }
    ArrayGet(type_idx) => {
      buf.write_string("array.get ")
      buf.write_string(type_idx.to_string())
    }
    ArrayGetS(type_idx) => {
      buf.write_string("array.get_s ")
      buf.write_string(type_idx.to_string())
    }
    ArrayGetU(type_idx) => {
      buf.write_string("array.get_u ")
      buf.write_string(type_idx.to_string())
    }
    ArraySet(type_idx) => {
      buf.write_string("array.set ")
      buf.write_string(type_idx.to_string())
    }
    ArrayLen => buf.write_string("array.len")
    ArrayFill(type_idx) => {
      buf.write_string("array.fill ")
      buf.write_string(type_idx.to_string())
    }
    ArrayCopy(dst_type, src_type) => {
      buf.write_string("array.copy ")
      buf.write_string(dst_type.to_string())
      buf.write_string(" ")
      buf.write_string(src_type.to_string())
    }
    ArrayInitData(type_idx, data_idx) => {
      buf.write_string("array.init_data ")
      buf.write_string(type_idx.to_string())
      buf.write_string(" ")
      buf.write_string(data_idx.to_string())
    }
    ArrayInitElem(type_idx, elem_idx) => {
      buf.write_string("array.init_elem ")
      buf.write_string(type_idx.to_string())
      buf.write_string(" ")
      buf.write_string(elem_idx.to_string())
    }

    // GC instructions - reference casting
    RefTest(_) => buf.write_string("ref.test")
    RefTestNull(_) => buf.write_string("ref.test null")
    RefCast(_) => buf.write_string("ref.cast")
    RefCastNull(_) => buf.write_string("ref.cast null")
    BrOnCast(label, _, _) => {
      buf.write_string("br_on_cast ")
      buf.write_string(label.to_string())
    }
    BrOnCastFail(label, _, _) => {
      buf.write_string("br_on_cast_fail ")
      buf.write_string(label.to_string())
    }

    // GC instructions - i31
    RefI31 => buf.write_string("ref.i31")
    I31GetS => buf.write_string("i31.get_s")
    I31GetU => buf.write_string("i31.get_u")

    // GC instructions - type conversion
    AnyConvertExtern => buf.write_string("any.convert_extern")
    ExternConvertAny => buf.write_string("extern.convert_any")

    // SIMD instructions
    V128Const(_) => buf.write_string("v128.const ...")
    V128Load(memidx, align, offset) =>
      write_mem_instr(buf, "v128.load", memidx, align, offset)
    V128Load8x8S(memidx, align, offset) =>
      write_mem_instr(buf, "v128.load8x8_s", memidx, align, offset)
    V128Load8x8U(memidx, align, offset) =>
      write_mem_instr(buf, "v128.load8x8_u", memidx, align, offset)
    V128Load16x4S(memidx, align, offset) =>
      write_mem_instr(buf, "v128.load16x4_s", memidx, align, offset)
    V128Load16x4U(memidx, align, offset) =>
      write_mem_instr(buf, "v128.load16x4_u", memidx, align, offset)
    V128Load32x2S(memidx, align, offset) =>
      write_mem_instr(buf, "v128.load32x2_s", memidx, align, offset)
    V128Load32x2U(memidx, align, offset) =>
      write_mem_instr(buf, "v128.load32x2_u", memidx, align, offset)
    V128Load8Splat(memidx, align, offset) =>
      write_mem_instr(buf, "v128.load8_splat", memidx, align, offset)
    V128Load16Splat(memidx, align, offset) =>
      write_mem_instr(buf, "v128.load16_splat", memidx, align, offset)
    V128Load32Splat(memidx, align, offset) =>
      write_mem_instr(buf, "v128.load32_splat", memidx, align, offset)
    V128Load64Splat(memidx, align, offset) =>
      write_mem_instr(buf, "v128.load64_splat", memidx, align, offset)
    V128Load32Zero(memidx, align, offset) =>
      write_mem_instr(buf, "v128.load32_zero", memidx, align, offset)
    V128Load64Zero(memidx, align, offset) =>
      write_mem_instr(buf, "v128.load64_zero", memidx, align, offset)
    V128Store(memidx, align, offset) =>
      write_mem_instr(buf, "v128.store", memidx, align, offset)
    V128Load8Lane(memidx, align, offset, lane) => {
      write_mem_instr(buf, "v128.load8_lane", memidx, align, offset)
      buf.write_string(" ")
      buf.write_string(lane.to_string())
    }
    V128Load16Lane(memidx, align, offset, lane) => {
      write_mem_instr(buf, "v128.load16_lane", memidx, align, offset)
      buf.write_string(" ")
      buf.write_string(lane.to_string())
    }
    V128Load32Lane(memidx, align, offset, lane) => {
      write_mem_instr(buf, "v128.load32_lane", memidx, align, offset)
      buf.write_string(" ")
      buf.write_string(lane.to_string())
    }
    V128Load64Lane(memidx, align, offset, lane) => {
      write_mem_instr(buf, "v128.load64_lane", memidx, align, offset)
      buf.write_string(" ")
      buf.write_string(lane.to_string())
    }
    V128Store8Lane(memidx, align, offset, lane) => {
      write_mem_instr(buf, "v128.store8_lane", memidx, align, offset)
      buf.write_string(" ")
      buf.write_string(lane.to_string())
    }
    V128Store16Lane(memidx, align, offset, lane) => {
      write_mem_instr(buf, "v128.store16_lane", memidx, align, offset)
      buf.write_string(" ")
      buf.write_string(lane.to_string())
    }
    V128Store32Lane(memidx, align, offset, lane) => {
      write_mem_instr(buf, "v128.store32_lane", memidx, align, offset)
      buf.write_string(" ")
      buf.write_string(lane.to_string())
    }
    V128Store64Lane(memidx, align, offset, lane) => {
      write_mem_instr(buf, "v128.store64_lane", memidx, align, offset)
      buf.write_string(" ")
      buf.write_string(lane.to_string())
    }
    I8x16Shuffle(_) => buf.write_string("i8x16.shuffle ...")
    I8x16Swizzle => buf.write_string("i8x16.swizzle")
    I8x16Splat => buf.write_string("i8x16.splat")
    I16x8Splat => buf.write_string("i16x8.splat")
    I32x4Splat => buf.write_string("i32x4.splat")
    I64x2Splat => buf.write_string("i64x2.splat")
    F32x4Splat => buf.write_string("f32x4.splat")
    F64x2Splat => buf.write_string("f64x2.splat")
    I8x16ExtractLaneS(lane) => {
      buf.write_string("i8x16.extract_lane_s ")
      buf.write_string(lane.to_string())
    }
    I8x16ExtractLaneU(lane) => {
      buf.write_string("i8x16.extract_lane_u ")
      buf.write_string(lane.to_string())
    }
    I16x8ExtractLaneS(lane) => {
      buf.write_string("i16x8.extract_lane_s ")
      buf.write_string(lane.to_string())
    }
    I16x8ExtractLaneU(lane) => {
      buf.write_string("i16x8.extract_lane_u ")
      buf.write_string(lane.to_string())
    }
    I32x4ExtractLane(lane) => {
      buf.write_string("i32x4.extract_lane ")
      buf.write_string(lane.to_string())
    }
    I64x2ExtractLane(lane) => {
      buf.write_string("i64x2.extract_lane ")
      buf.write_string(lane.to_string())
    }
    F32x4ExtractLane(lane) => {
      buf.write_string("f32x4.extract_lane ")
      buf.write_string(lane.to_string())
    }
    F64x2ExtractLane(lane) => {
      buf.write_string("f64x2.extract_lane ")
      buf.write_string(lane.to_string())
    }
    I8x16ReplaceLane(lane) => {
      buf.write_string("i8x16.replace_lane ")
      buf.write_string(lane.to_string())
    }
    I16x8ReplaceLane(lane) => {
      buf.write_string("i16x8.replace_lane ")
      buf.write_string(lane.to_string())
    }
    I32x4ReplaceLane(lane) => {
      buf.write_string("i32x4.replace_lane ")
      buf.write_string(lane.to_string())
    }
    I64x2ReplaceLane(lane) => {
      buf.write_string("i64x2.replace_lane ")
      buf.write_string(lane.to_string())
    }
    F32x4ReplaceLane(lane) => {
      buf.write_string("f32x4.replace_lane ")
      buf.write_string(lane.to_string())
    }
    F64x2ReplaceLane(lane) => {
      buf.write_string("f64x2.replace_lane ")
      buf.write_string(lane.to_string())
    }
    I8x16Eq => buf.write_string("i8x16.eq")
    I8x16Ne => buf.write_string("i8x16.ne")
    I8x16LtS => buf.write_string("i8x16.lt_s")
    I8x16LtU => buf.write_string("i8x16.lt_u")
    I8x16GtS => buf.write_string("i8x16.gt_s")
    I8x16GtU => buf.write_string("i8x16.gt_u")
    I8x16LeS => buf.write_string("i8x16.le_s")
    I8x16LeU => buf.write_string("i8x16.le_u")
    I8x16GeS => buf.write_string("i8x16.ge_s")
    I8x16GeU => buf.write_string("i8x16.ge_u")
    I16x8Eq => buf.write_string("i16x8.eq")
    I16x8Ne => buf.write_string("i16x8.ne")
    I16x8LtS => buf.write_string("i16x8.lt_s")
    I16x8LtU => buf.write_string("i16x8.lt_u")
    I16x8GtS => buf.write_string("i16x8.gt_s")
    I16x8GtU => buf.write_string("i16x8.gt_u")
    I16x8LeS => buf.write_string("i16x8.le_s")
    I16x8LeU => buf.write_string("i16x8.le_u")
    I16x8GeS => buf.write_string("i16x8.ge_s")
    I16x8GeU => buf.write_string("i16x8.ge_u")
    I32x4Eq => buf.write_string("i32x4.eq")
    I32x4Ne => buf.write_string("i32x4.ne")
    I32x4LtS => buf.write_string("i32x4.lt_s")
    I32x4LtU => buf.write_string("i32x4.lt_u")
    I32x4GtS => buf.write_string("i32x4.gt_s")
    I32x4GtU => buf.write_string("i32x4.gt_u")
    I32x4LeS => buf.write_string("i32x4.le_s")
    I32x4LeU => buf.write_string("i32x4.le_u")
    I32x4GeS => buf.write_string("i32x4.ge_s")
    I32x4GeU => buf.write_string("i32x4.ge_u")
    I64x2Eq => buf.write_string("i64x2.eq")
    I64x2Ne => buf.write_string("i64x2.ne")
    I64x2LtS => buf.write_string("i64x2.lt_s")
    I64x2GtS => buf.write_string("i64x2.gt_s")
    I64x2LeS => buf.write_string("i64x2.le_s")
    I64x2GeS => buf.write_string("i64x2.ge_s")
    F32x4Eq => buf.write_string("f32x4.eq")
    F32x4Ne => buf.write_string("f32x4.ne")
    F32x4Lt => buf.write_string("f32x4.lt")
    F32x4Gt => buf.write_string("f32x4.gt")
    F32x4Le => buf.write_string("f32x4.le")
    F32x4Ge => buf.write_string("f32x4.ge")
    F64x2Eq => buf.write_string("f64x2.eq")
    F64x2Ne => buf.write_string("f64x2.ne")
    F64x2Lt => buf.write_string("f64x2.lt")
    F64x2Gt => buf.write_string("f64x2.gt")
    F64x2Le => buf.write_string("f64x2.le")
    F64x2Ge => buf.write_string("f64x2.ge")
    V128Not => buf.write_string("v128.not")
    V128And => buf.write_string("v128.and")
    V128AndNot => buf.write_string("v128.andnot")
    V128Or => buf.write_string("v128.or")
    V128Xor => buf.write_string("v128.xor")
    V128Bitselect => buf.write_string("v128.bitselect")
    V128AnyTrue => buf.write_string("v128.any_true")
    I8x16Abs => buf.write_string("i8x16.abs")
    I8x16Neg => buf.write_string("i8x16.neg")
    I8x16Popcnt => buf.write_string("i8x16.popcnt")
    I8x16AllTrue => buf.write_string("i8x16.all_true")
    I8x16Bitmask => buf.write_string("i8x16.bitmask")
    I8x16NarrowI16x8S => buf.write_string("i8x16.narrow_i16x8_s")
    I8x16NarrowI16x8U => buf.write_string("i8x16.narrow_i16x8_u")
    I8x16Shl => buf.write_string("i8x16.shl")
    I8x16ShrS => buf.write_string("i8x16.shr_s")
    I8x16ShrU => buf.write_string("i8x16.shr_u")
    I8x16Add => buf.write_string("i8x16.add")
    I8x16AddSatS => buf.write_string("i8x16.add_sat_s")
    I8x16AddSatU => buf.write_string("i8x16.add_sat_u")
    I8x16Sub => buf.write_string("i8x16.sub")
    I8x16SubSatS => buf.write_string("i8x16.sub_sat_s")
    I8x16SubSatU => buf.write_string("i8x16.sub_sat_u")
    I8x16MinS => buf.write_string("i8x16.min_s")
    I8x16MinU => buf.write_string("i8x16.min_u")
    I8x16MaxS => buf.write_string("i8x16.max_s")
    I8x16MaxU => buf.write_string("i8x16.max_u")
    I8x16AvgrU => buf.write_string("i8x16.avgr_u")
    I16x8ExtAddPairwiseI8x16S =>
      buf.write_string("i16x8.extadd_pairwise_i8x16_s")
    I16x8ExtAddPairwiseI8x16U =>
      buf.write_string("i16x8.extadd_pairwise_i8x16_u")
    I16x8Abs => buf.write_string("i16x8.abs")
    I16x8Neg => buf.write_string("i16x8.neg")
    I16x8Q15MulrSatS => buf.write_string("i16x8.q15mulr_sat_s")
    I16x8AllTrue => buf.write_string("i16x8.all_true")
    I16x8Bitmask => buf.write_string("i16x8.bitmask")
    I16x8NarrowI32x4S => buf.write_string("i16x8.narrow_i32x4_s")
    I16x8NarrowI32x4U => buf.write_string("i16x8.narrow_i32x4_u")
    I16x8ExtendLowI8x16S => buf.write_string("i16x8.extend_low_i8x16_s")
    I16x8ExtendHighI8x16S => buf.write_string("i16x8.extend_high_i8x16_s")
    I16x8ExtendLowI8x16U => buf.write_string("i16x8.extend_low_i8x16_u")
    I16x8ExtendHighI8x16U => buf.write_string("i16x8.extend_high_i8x16_u")
    I16x8Shl => buf.write_string("i16x8.shl")
    I16x8ShrS => buf.write_string("i16x8.shr_s")
    I16x8ShrU => buf.write_string("i16x8.shr_u")
    I16x8Add => buf.write_string("i16x8.add")
    I16x8AddSatS => buf.write_string("i16x8.add_sat_s")
    I16x8AddSatU => buf.write_string("i16x8.add_sat_u")
    I16x8Sub => buf.write_string("i16x8.sub")
    I16x8SubSatS => buf.write_string("i16x8.sub_sat_s")
    I16x8SubSatU => buf.write_string("i16x8.sub_sat_u")
    I16x8Mul => buf.write_string("i16x8.mul")
    I16x8MinS => buf.write_string("i16x8.min_s")
    I16x8MinU => buf.write_string("i16x8.min_u")
    I16x8MaxS => buf.write_string("i16x8.max_s")
    I16x8MaxU => buf.write_string("i16x8.max_u")
    I16x8AvgrU => buf.write_string("i16x8.avgr_u")
    I16x8ExtMulLowI8x16S => buf.write_string("i16x8.extmul_low_i8x16_s")
    I16x8ExtMulHighI8x16S => buf.write_string("i16x8.extmul_high_i8x16_s")
    I16x8ExtMulLowI8x16U => buf.write_string("i16x8.extmul_low_i8x16_u")
    I16x8ExtMulHighI8x16U => buf.write_string("i16x8.extmul_high_i8x16_u")
    I32x4ExtAddPairwiseI16x8S =>
      buf.write_string("i32x4.extadd_pairwise_i16x8_s")
    I32x4ExtAddPairwiseI16x8U =>
      buf.write_string("i32x4.extadd_pairwise_i16x8_u")
    I32x4Abs => buf.write_string("i32x4.abs")
    I32x4Neg => buf.write_string("i32x4.neg")
    I32x4AllTrue => buf.write_string("i32x4.all_true")
    I32x4Bitmask => buf.write_string("i32x4.bitmask")
    I32x4ExtendLowI16x8S => buf.write_string("i32x4.extend_low_i16x8_s")
    I32x4ExtendHighI16x8S => buf.write_string("i32x4.extend_high_i16x8_s")
    I32x4ExtendLowI16x8U => buf.write_string("i32x4.extend_low_i16x8_u")
    I32x4ExtendHighI16x8U => buf.write_string("i32x4.extend_high_i16x8_u")
    I32x4Shl => buf.write_string("i32x4.shl")
    I32x4ShrS => buf.write_string("i32x4.shr_s")
    I32x4ShrU => buf.write_string("i32x4.shr_u")
    I32x4Add => buf.write_string("i32x4.add")
    I32x4Sub => buf.write_string("i32x4.sub")
    I32x4Mul => buf.write_string("i32x4.mul")
    I32x4MinS => buf.write_string("i32x4.min_s")
    I32x4MinU => buf.write_string("i32x4.min_u")
    I32x4MaxS => buf.write_string("i32x4.max_s")
    I32x4MaxU => buf.write_string("i32x4.max_u")
    I32x4DotI16x8S => buf.write_string("i32x4.dot_i16x8_s")
    I32x4ExtMulLowI16x8S => buf.write_string("i32x4.extmul_low_i16x8_s")
    I32x4ExtMulHighI16x8S => buf.write_string("i32x4.extmul_high_i16x8_s")
    I32x4ExtMulLowI16x8U => buf.write_string("i32x4.extmul_low_i16x8_u")
    I32x4ExtMulHighI16x8U => buf.write_string("i32x4.extmul_high_i16x8_u")
    I64x2Abs => buf.write_string("i64x2.abs")
    I64x2Neg => buf.write_string("i64x2.neg")
    I64x2AllTrue => buf.write_string("i64x2.all_true")
    I64x2Bitmask => buf.write_string("i64x2.bitmask")
    I64x2ExtendLowI32x4S => buf.write_string("i64x2.extend_low_i32x4_s")
    I64x2ExtendHighI32x4S => buf.write_string("i64x2.extend_high_i32x4_s")
    I64x2ExtendLowI32x4U => buf.write_string("i64x2.extend_low_i32x4_u")
    I64x2ExtendHighI32x4U => buf.write_string("i64x2.extend_high_i32x4_u")
    I64x2Shl => buf.write_string("i64x2.shl")
    I64x2ShrS => buf.write_string("i64x2.shr_s")
    I64x2ShrU => buf.write_string("i64x2.shr_u")
    I64x2Add => buf.write_string("i64x2.add")
    I64x2Sub => buf.write_string("i64x2.sub")
    I64x2Mul => buf.write_string("i64x2.mul")
    I64x2ExtMulLowI32x4S => buf.write_string("i64x2.extmul_low_i32x4_s")
    I64x2ExtMulHighI32x4S => buf.write_string("i64x2.extmul_high_i32x4_s")
    I64x2ExtMulLowI32x4U => buf.write_string("i64x2.extmul_low_i32x4_u")
    I64x2ExtMulHighI32x4U => buf.write_string("i64x2.extmul_high_i32x4_u")
    F32x4Ceil => buf.write_string("f32x4.ceil")
    F32x4Floor => buf.write_string("f32x4.floor")
    F32x4Trunc => buf.write_string("f32x4.trunc")
    F32x4Nearest => buf.write_string("f32x4.nearest")
    F32x4Abs => buf.write_string("f32x4.abs")
    F32x4Neg => buf.write_string("f32x4.neg")
    F32x4Sqrt => buf.write_string("f32x4.sqrt")
    F32x4Add => buf.write_string("f32x4.add")
    F32x4Sub => buf.write_string("f32x4.sub")
    F32x4Mul => buf.write_string("f32x4.mul")
    F32x4Div => buf.write_string("f32x4.div")
    F32x4Min => buf.write_string("f32x4.min")
    F32x4Max => buf.write_string("f32x4.max")
    F32x4Pmin => buf.write_string("f32x4.pmin")
    F32x4Pmax => buf.write_string("f32x4.pmax")
    F64x2Ceil => buf.write_string("f64x2.ceil")
    F64x2Floor => buf.write_string("f64x2.floor")
    F64x2Trunc => buf.write_string("f64x2.trunc")
    F64x2Nearest => buf.write_string("f64x2.nearest")
    F64x2Abs => buf.write_string("f64x2.abs")
    F64x2Neg => buf.write_string("f64x2.neg")
    F64x2Sqrt => buf.write_string("f64x2.sqrt")
    F64x2Add => buf.write_string("f64x2.add")
    F64x2Sub => buf.write_string("f64x2.sub")
    F64x2Mul => buf.write_string("f64x2.mul")
    F64x2Div => buf.write_string("f64x2.div")
    F64x2Min => buf.write_string("f64x2.min")
    F64x2Max => buf.write_string("f64x2.max")
    F64x2Pmin => buf.write_string("f64x2.pmin")
    F64x2Pmax => buf.write_string("f64x2.pmax")
    I32x4TruncSatF32x4S => buf.write_string("i32x4.trunc_sat_f32x4_s")
    I32x4TruncSatF32x4U => buf.write_string("i32x4.trunc_sat_f32x4_u")
    F32x4ConvertI32x4S => buf.write_string("f32x4.convert_i32x4_s")
    F32x4ConvertI32x4U => buf.write_string("f32x4.convert_i32x4_u")
    I32x4TruncSatF64x2SZero => buf.write_string("i32x4.trunc_sat_f64x2_s_zero")
    I32x4TruncSatF64x2UZero => buf.write_string("i32x4.trunc_sat_f64x2_u_zero")
    F64x2ConvertLowI32x4S => buf.write_string("f64x2.convert_low_i32x4_s")
    F64x2ConvertLowI32x4U => buf.write_string("f64x2.convert_low_i32x4_u")
    F32x4DemoteF64x2Zero => buf.write_string("f32x4.demote_f64x2_zero")
    F64x2PromoteLowF32x4 => buf.write_string("f64x2.promote_low_f32x4")
    // Relaxed SIMD instructions
    I8x16RelaxedSwizzle => buf.write_string("i8x16.relaxed_swizzle")
    I32x4RelaxedTruncF32x4S => buf.write_string("i32x4.relaxed_trunc_f32x4_s")
    I32x4RelaxedTruncF32x4U => buf.write_string("i32x4.relaxed_trunc_f32x4_u")
    I32x4RelaxedTruncF64x2SZero =>
      buf.write_string("i32x4.relaxed_trunc_f64x2_s_zero")
    I32x4RelaxedTruncF64x2UZero =>
      buf.write_string("i32x4.relaxed_trunc_f64x2_u_zero")
    F32x4RelaxedMadd => buf.write_string("f32x4.relaxed_madd")
    F32x4RelaxedNmadd => buf.write_string("f32x4.relaxed_nmadd")
    F64x2RelaxedMadd => buf.write_string("f64x2.relaxed_madd")
    F64x2RelaxedNmadd => buf.write_string("f64x2.relaxed_nmadd")
    I8x16RelaxedLaneselect => buf.write_string("i8x16.relaxed_laneselect")
    I16x8RelaxedLaneselect => buf.write_string("i16x8.relaxed_laneselect")
    I32x4RelaxedLaneselect => buf.write_string("i32x4.relaxed_laneselect")
    I64x2RelaxedLaneselect => buf.write_string("i64x2.relaxed_laneselect")
    F32x4RelaxedMin => buf.write_string("f32x4.relaxed_min")
    F32x4RelaxedMax => buf.write_string("f32x4.relaxed_max")
    F64x2RelaxedMin => buf.write_string("f64x2.relaxed_min")
    F64x2RelaxedMax => buf.write_string("f64x2.relaxed_max")
    I16x8RelaxedQ15mulrS => buf.write_string("i16x8.relaxed_q15mulr_s")
    I16x8RelaxedDotI8x16I7x16S =>
      buf.write_string("i16x8.relaxed_dot_i8x16_i7x16_s")
    I32x4RelaxedDotI8x16I7x16AddS =>
      buf.write_string("i32x4.relaxed_dot_i8x16_i7x16_add_s")
  }
}

///|
fn write_mem_instr(
  buf : StringBuilder,
  name : String,
  memidx : Int,
  align : Int,
  offset : Int64,
) -> Unit {
  buf.write_string(name)
  if memidx != 0 {
    buf.write_string(" ")
    buf.write_string(memidx.to_string())
  }
  if offset != 0L {
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
