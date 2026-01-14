///|
/// Convert a Module to WAT text format
fn module_to_wat(mod_ : @types.Module) -> String {
  let sb = StringBuilder::new()
  sb.write_string("(module\n")

  // Types section
  for i, subtype in mod_.types {
    match subtype.composite {
      Func(ft) => {
        sb.write_string("  (type (;")
        sb.write_string(i.to_string())
        sb.write_string(";) (func")
        for param in ft.params {
          sb.write_string(" (param ")
          sb.write_string(value_type_to_wat(param))
          sb.write_string(")")
        }
        for result in ft.results {
          sb.write_string(" (result ")
          sb.write_string(value_type_to_wat(result))
          sb.write_string(")")
        }
        sb.write_string("))\n")
      }
      Struct(st) => {
        sb.write_string("  (type (;")
        sb.write_string(i.to_string())
        sb.write_string(";) (struct")
        for field in st.fields {
          sb.write_string(" (field ")
          if field.mutable {
            sb.write_string("(mut ")
          }
          sb.write_string(storage_type_to_wat(field.storage_type))
          if field.mutable {
            sb.write_string(")")
          }
          sb.write_string(")")
        }
        sb.write_string("))\n")
      }
      Array(at) => {
        sb.write_string("  (type (;")
        sb.write_string(i.to_string())
        sb.write_string(";) (array ")
        if at.element.mutable {
          sb.write_string("(mut ")
        }
        sb.write_string(storage_type_to_wat(at.element.storage_type))
        if at.element.mutable {
          sb.write_string(")")
        }
        sb.write_string("))\n")
      }
    }
  }

  // Imports section
  for imp in mod_.imports {
    sb.write_string("  (import \"")
    sb.write_string(imp.mod_name)
    sb.write_string("\" \"")
    sb.write_string(imp.name)
    sb.write_string("\" ")
    match imp.desc {
      Func(type_idx) => {
        sb.write_string("(func (type ")
        sb.write_string(type_idx.to_string())
        sb.write_string("))")
      }
      Table(table_type) => {
        sb.write_string("(table ")
        sb.write_string(limits_to_wat(table_type.limits))
        sb.write_string(" ")
        sb.write_string(value_type_to_wat(table_type.elem_type))
        sb.write_string(")")
      }
      Memory(mem_type) => {
        sb.write_string("(memory ")
        sb.write_string(limits_to_wat(mem_type.limits))
        sb.write_string(")")
      }
      Global(global_type) => {
        sb.write_string("(global ")
        if global_type.mutable {
          sb.write_string("(mut ")
          sb.write_string(value_type_to_wat(global_type.value_type))
          sb.write_string(")")
        } else {
          sb.write_string(value_type_to_wat(global_type.value_type))
        }
        sb.write_string(")")
      }
      Tag(type_idx) => {
        sb.write_string("(tag (type ")
        sb.write_string(type_idx.to_string())
        sb.write_string("))")
      }
    }
    sb.write_string(")\n")
  }

  // Count imported functions for indexing
  let mut import_func_count = 0
  for imp in mod_.imports {
    match imp.desc {
      Func(_) => import_func_count = import_func_count + 1
      _ => ()
    }
  }

  // Tables section
  for i, table in mod_.tables {
    sb.write_string("  (table (;")
    sb.write_string(i.to_string())
    sb.write_string(";) ")
    sb.write_string(limits_to_wat(table.type_.limits))
    sb.write_string(" ")
    sb.write_string(value_type_to_wat(table.type_.elem_type))
    sb.write_string(")\n")
  }

  // Memories section
  for i, mem in mod_.memories {
    sb.write_string("  (memory (;")
    sb.write_string(i.to_string())
    sb.write_string(";) ")
    sb.write_string(limits_to_wat(mem.limits))
    sb.write_string(")\n")
  }

  // Globals section
  for i, global in mod_.globals {
    sb.write_string("  (global (;")
    sb.write_string(i.to_string())
    sb.write_string(";) ")
    if global.type_.mutable {
      sb.write_string("(mut ")
      sb.write_string(value_type_to_wat(global.type_.value_type))
      sb.write_string(")")
    } else {
      sb.write_string(value_type_to_wat(global.type_.value_type))
    }
    sb.write_string(" (")
    sb.write_string(instrs_to_wat_inline(global.init))
    sb.write_string("))\n")
  }

  // Exports section
  for exp in mod_.exports {
    sb.write_string("  (export \"")
    sb.write_string(exp.name)
    sb.write_string("\" (")
    match exp.desc {
      Func(idx) => {
        sb.write_string("func ")
        sb.write_string(idx.to_string())
      }
      Table(idx) => {
        sb.write_string("table ")
        sb.write_string(idx.to_string())
      }
      Memory(idx) => {
        sb.write_string("memory ")
        sb.write_string(idx.to_string())
      }
      Global(idx) => {
        sb.write_string("global ")
        sb.write_string(idx.to_string())
      }
      Tag(idx) => {
        sb.write_string("tag ")
        sb.write_string(idx.to_string())
      }
    }
    sb.write_string("))\n")
  }

  // Start section
  match mod_.start {
    Some(start_idx) => {
      sb.write_string("  (start ")
      sb.write_string(start_idx.to_string())
      sb.write_string(")\n")
    }
    None => ()
  }

  // Elements section
  for i, elem in mod_.elems {
    sb.write_string("  (elem (;")
    sb.write_string(i.to_string())
    sb.write_string(";) ")
    match elem.mode {
      Passive => ()
      Declarative => sb.write_string("declare ")
      Active(table_idx, offset) => {
        if table_idx != 0 {
          sb.write_string("(table ")
          sb.write_string(table_idx.to_string())
          sb.write_string(") ")
        }
        sb.write_string("(")
        sb.write_string(instrs_to_wat_inline(offset))
        sb.write_string(") ")
      }
    }
    sb.write_string(value_type_to_wat(elem.type_))
    for init in elem.init {
      sb.write_string(" (")
      sb.write_string(instrs_to_wat_inline(init))
      sb.write_string(")")
    }
    sb.write_string(")\n")
  }

  // Functions section (code)
  for i, code in mod_.codes {
    let func_idx = import_func_count + i
    let type_idx = mod_.funcs[i]
    let func_type = mod_.get_func_type(type_idx)
    sb.write_string("  (func (;")
    sb.write_string(func_idx.to_string())
    sb.write_string(";) (type ")
    sb.write_string(type_idx.to_string())
    sb.write_string(")")
    for param in func_type.params {
      sb.write_string(" (param ")
      sb.write_string(value_type_to_wat(param))
      sb.write_string(")")
    }
    for result in func_type.results {
      sb.write_string(" (result ")
      sb.write_string(value_type_to_wat(result))
      sb.write_string(")")
    }
    sb.write_string("\n")
    // Locals
    for loc in code.locals {
      sb.write_string("    (local ")
      sb.write_string(value_type_to_wat(loc))
      sb.write_string(")\n")
    }
    // Body
    sb.write_string(instrs_to_wat(code.body, 2))
    sb.write_string("  )\n")
  }

  // Data section
  for i, data in mod_.datas {
    sb.write_string("  (data (;")
    sb.write_string(i.to_string())
    sb.write_string(";) ")
    // Active data segments have memory_idx and offset
    if data.memory_idx != 0 {
      sb.write_string("(memory ")
      sb.write_string(data.memory_idx.to_string())
      sb.write_string(") ")
    }
    if data.offset.length() > 0 {
      sb.write_string("(")
      sb.write_string(instrs_to_wat_inline(data.offset))
      sb.write_string(") ")
    }
    sb.write_string("\"")
    sb.write_string(escape_data_string(data.init))
    sb.write_string("\")\n")
  }
  sb.write_string(")\n")
  sb.to_string()
}

///|
fn escape_data_string(data : Bytes) -> String {
  let sb = StringBuilder::new()
  for b in data {
    let c = b.to_int()
    if c >= 32 && c < 127 && c != 0x22 && c != 0x5c {
      // Printable ASCII (except " and \)
      sb.write_char(c.unsafe_to_char())
    } else {
      // Escape as hex
      sb.write_string("\\")
      let hex = "0123456789abcdef"
      sb.write_char(hex[(c >> 4) & 0xf].to_int().unsafe_to_char())
      sb.write_char(hex[c & 0xf].to_int().unsafe_to_char())
    }
  }
  sb.to_string()
}

///|
fn limits_to_wat(limits : @types.Limits) -> String {
  match limits.max {
    Some(max) => "\{limits.min} \{max}"
    None => limits.min.to_string()
  }
}

///|
fn storage_type_to_wat(st : @types.StorageType) -> String {
  match st {
    Val(vt) => value_type_to_wat(vt)
    Packed(I8) => "i8"
    Packed(I16) => "i16"
  }
}

///|
fn instrs_to_wat_inline(instrs : Array[@types.Instruction]) -> String {
  let parts : Array[String] = []
  for instr in instrs {
    parts.push(instr_to_wat(instr))
  }
  parts.join(" ")
}

///|
fn value_type_to_wat(t : @types.ValueType) -> String {
  match t {
    I32 => "i32"
    I64 => "i64"
    F32 => "f32"
    F64 => "f64"
    V128 => "v128"
    FuncRef => "funcref"
    ExternRef => "externref"
    RefFunc => "(ref func)"
    RefExtern => "(ref extern)"
    RefFuncTyped(idx) => "(ref \{idx})"
    RefNullFuncTyped(idx) => "(ref null \{idx})"
    AnyRef => "anyref"
    ExnRef => "exnref"
    StructRef => "structref"
    ArrayRef => "arrayref"
    RefStruct(idx) => "(ref \{idx})"
    RefNullStruct(idx) => "(ref null \{idx})"
    RefArray(idx) => "(ref \{idx})"
    RefNullArray(idx) => "(ref null \{idx})"
    RefAny => "(ref any)"
    RefEq => "(ref eq)"
    RefNullEq => "(ref null eq)"
    RefI31 => "(ref i31)"
    RefNullI31 => "(ref null i31)"
    RefStructAbs => "(ref struct)"
    RefArrayAbs => "(ref array)"
    RefNone => "(ref none)"
    NullRef => "nullref"
    NullFuncRef => "nullfuncref"
    NullExnRef => "nullexnref"
    NullExternRef => "nullexternref"
  }
}

///|
fn block_type_to_wat(bt : @types.BlockType) -> String {
  match bt {
    Empty => ""
    Value(t) => " (result \{value_type_to_wat(t)})"
    MultiValue(types) => {
      let types_str = types.map(fn(t) { value_type_to_wat(t) }).join(" ")
      " (result \{types_str})"
    }
    InlineType(params, results) => {
      let params_str = if params.is_empty() {
        ""
      } else {
        let p = params.map(fn(t) { value_type_to_wat(t) }).join(" ")
        " (param \{p})"
      }
      let results_str = if results.is_empty() {
        ""
      } else {
        let r = results.map(fn(t) { value_type_to_wat(t) }).join(" ")
        " (result \{r})"
      }
      "\{params_str}\{results_str}"
    }
    TypeIndex(idx) => " (type \{idx})"
  }
}

///|
fn ref_type_to_wat(t : @types.ValueType) -> String {
  match t {
    FuncRef => "funcref"
    ExternRef => "externref"
    AnyRef => "anyref"
    ExnRef => "exnref"
    RefFunc => "(ref func)"
    RefExtern => "(ref extern)"
    RefAny => "(ref any)"
    RefEq => "(ref eq)"
    RefI31 => "(ref i31)"
    RefFuncTyped(idx) => "(ref \{idx})"
    RefNullFuncTyped(idx) => "(ref null \{idx})"
    RefStruct(idx) => "(ref \{idx})"
    RefNullStruct(idx) => "(ref null \{idx})"
    RefArray(idx) => "(ref \{idx})"
    RefNullArray(idx) => "(ref null \{idx})"
    _ => value_type_to_wat(t)
  }
}

///|
fn heap_type_to_wat(t : @types.ValueType) -> String {
  match t {
    FuncRef | RefFunc => "func"
    ExternRef | RefExtern => "extern"
    AnyRef | RefAny => "any"
    ExnRef => "exn"
    RefEq | RefNullEq => "eq"
    RefI31 | RefNullI31 => "i31"
    RefFuncTyped(idx) | RefNullFuncTyped(idx) => idx.to_string()
    RefStruct(idx) | RefNullStruct(idx) => idx.to_string()
    RefArray(idx) | RefNullArray(idx) => idx.to_string()
    _ => "any"
  }
}

///|
fn mem_instr(
  name : String,
  mem : Int,
  align : Int,
  offset : Int64,
  natural_align : Int,
) -> String {
  let sb = StringBuilder::new()
  sb.write_string(name)
  if mem != 0 {
    sb.write_string(" \{mem}")
  }
  if offset != 0L {
    sb.write_string(" offset=\{offset}")
  }
  if align != natural_align {
    let align_bytes = 1 << align
    sb.write_string(" align=\{align_bytes}")
  }
  sb.to_string()
}

///|
fn format_v128_bytes(bytes : Bytes) -> String {
  let parts : Array[String] = []
  for i = 0; i < 16; i = i + 1 {
    let b = if i < bytes.length() { bytes[i].to_int() } else { 0 }
    parts.push(b.to_string())
  }
  parts.join(" ")
}

///|
fn instrs_to_wat(instrs : Array[@types.Instruction], indent : Int) -> String {
  let sb = StringBuilder::new()
  let indent_str = "  ".repeat(indent)
  for instr in instrs {
    sb.write_string(indent_str)
    sb.write_string(instr_to_wat(instr))
    sb.write_string("\n")
    match instr {
      Block(_, body) | Loop(_, body) => {
        sb.write_string(instrs_to_wat(body, indent + 1))
        sb.write_string(indent_str)
        sb.write_string("end\n")
      }
      If(_, then_body, else_body) => {
        sb.write_string(instrs_to_wat(then_body, indent + 1))
        if not(else_body.is_empty()) {
          sb.write_string(indent_str)
          sb.write_string("else\n")
          sb.write_string(instrs_to_wat(else_body, indent + 1))
        }
        sb.write_string(indent_str)
        sb.write_string("end\n")
      }
      TryTable(_, _, body) => {
        sb.write_string(instrs_to_wat(body, indent + 1))
        sb.write_string(indent_str)
        sb.write_string("end\n")
      }
      _ => ()
    }
  }
  sb.to_string()
}

///|
fn instr_to_wat(instr : @types.Instruction) -> String {
  fn atomic_instr(
    subop : Int,
    mem : Int,
    align : Int,
    offset : Int64,
  ) -> String {
    let name = match subop {
      0 => "memory.atomic.notify"
      1 => "memory.atomic.wait32"
      2 => "memory.atomic.wait64"
      3 => "atomic.fence"
      4 => "i32.atomic.load"
      5 => "i64.atomic.load"
      6 => "i32.atomic.load8_u"
      7 => "i32.atomic.load16_u"
      8 => "i64.atomic.load8_u"
      9 => "i64.atomic.load16_u"
      10 => "i64.atomic.load32_u"
      11 => "i32.atomic.store"
      12 => "i64.atomic.store"
      13 => "i32.atomic.store8"
      14 => "i32.atomic.store16"
      15 => "i64.atomic.store8"
      16 => "i64.atomic.store16"
      17 => "i64.atomic.store32"
      18 => "i32.atomic.rmw.add"
      19 => "i64.atomic.rmw.add"
      20 => "i32.atomic.rmw8.add_u"
      21 => "i32.atomic.rmw16.add_u"
      22 => "i64.atomic.rmw8.add_u"
      23 => "i64.atomic.rmw16.add_u"
      24 => "i64.atomic.rmw32.add_u"
      25 => "i32.atomic.rmw.sub"
      26 => "i64.atomic.rmw.sub"
      27 => "i32.atomic.rmw8.sub_u"
      28 => "i32.atomic.rmw16.sub_u"
      29 => "i64.atomic.rmw8.sub_u"
      30 => "i64.atomic.rmw16.sub_u"
      31 => "i64.atomic.rmw32.sub_u"
      32 => "i32.atomic.rmw.and"
      33 => "i64.atomic.rmw.and"
      34 => "i32.atomic.rmw8.and_u"
      35 => "i32.atomic.rmw16.and_u"
      36 => "i64.atomic.rmw8.and_u"
      37 => "i64.atomic.rmw16.and_u"
      38 => "i64.atomic.rmw32.and_u"
      39 => "i32.atomic.rmw.or"
      40 => "i64.atomic.rmw.or"
      41 => "i32.atomic.rmw8.or_u"
      42 => "i32.atomic.rmw16.or_u"
      43 => "i64.atomic.rmw8.or_u"
      44 => "i64.atomic.rmw16.or_u"
      45 => "i64.atomic.rmw32.or_u"
      46 => "i32.atomic.rmw.xor"
      47 => "i64.atomic.rmw.xor"
      48 => "i32.atomic.rmw8.xor_u"
      49 => "i32.atomic.rmw16.xor_u"
      50 => "i64.atomic.rmw8.xor_u"
      51 => "i64.atomic.rmw16.xor_u"
      52 => "i64.atomic.rmw32.xor_u"
      53 => "i32.atomic.rmw.xchg"
      54 => "i64.atomic.rmw.xchg"
      55 => "i32.atomic.rmw8.xchg_u"
      56 => "i32.atomic.rmw16.xchg_u"
      57 => "i64.atomic.rmw8.xchg_u"
      58 => "i64.atomic.rmw16.xchg_u"
      59 => "i64.atomic.rmw32.xchg_u"
      60 => "i32.atomic.rmw.cmpxchg"
      61 => "i64.atomic.rmw.cmpxchg"
      62 => "i32.atomic.rmw8.cmpxchg_u"
      63 => "i32.atomic.rmw16.cmpxchg_u"
      64 => "i64.atomic.rmw8.cmpxchg_u"
      65 => "i64.atomic.rmw16.cmpxchg_u"
      66 => "i64.atomic.rmw32.cmpxchg_u"
      _ => "atomic.unknown"
    }
    let natural_align = match subop {
      0 | 1 | 4 | 10 | 11 | 18 | 25 | 32 | 39 | 46 | 53 | 60 => 2
      2 | 5 | 12 | 19 | 26 | 33 | 40 | 47 | 54 | 61 => 3
      6
      | 8
      | 13
      | 15
      | 20
      | 22
      | 27
      | 29
      | 34
      | 36
      | 41
      | 43
      | 48
      | 50
      | 55
      | 57
      | 62
      | 64 => 0
      7
      | 9
      | 14
      | 16
      | 21
      | 23
      | 28
      | 30
      | 35
      | 37
      | 42
      | 44
      | 49
      | 51
      | 56
      | 58
      | 63
      | 65 => 1
      17 | 24 | 31 | 38 | 45 | 52 | 59 | 66 => 2
      _ => 0
    }
    if subop == 3 {
      name
    } else {
      mem_instr(name, mem, align, offset, natural_align)
    }
  }

  match instr {
    Unreachable => "unreachable"
    Nop => "nop"
    Block(bt, _) => "block\{block_type_to_wat(bt)}"
    Loop(bt, _) => "loop\{block_type_to_wat(bt)}"
    If(bt, _, _) => "if\{block_type_to_wat(bt)}"
    Br(idx) => "br \{idx}"
    BrIf(idx) => "br_if \{idx}"
    BrTable(labels, default) => {
      let labels_str = labels.map(fn(l) { l.to_string() }).join(" ")
      "br_table \{labels_str} \{default}"
    }
    Return => "return"
    Call(idx) => "call \{idx}"
    CallIndirect(type_idx, table_idx) =>
      if table_idx == 0 {
        "call_indirect (type \{type_idx})"
      } else {
        "call_indirect \{table_idx} (type \{type_idx})"
      }
    CallRef(type_idx) => "call_ref \{type_idx}"
    ReturnCall(idx) => "return_call \{idx}"
    ReturnCallIndirect(type_idx, table_idx) =>
      if table_idx == 0 {
        "return_call_indirect (type \{type_idx})"
      } else {
        "return_call_indirect \{table_idx} (type \{type_idx})"
      }
    ReturnCallRef(type_idx) => "return_call_ref \{type_idx}"
    Throw(idx) => "throw \{idx}"
    ThrowRef => "throw_ref"
    TryTable(bt, _, _) => "try_table\{block_type_to_wat(bt)}"
    Drop => "drop"
    Select => "select"
    SelectTyped(types) => {
      let types_str = types.map(fn(t) { value_type_to_wat(t) }).join(" ")
      "select (result \{types_str})"
    }
    LocalGet(idx) => "local.get \{idx}"
    LocalSet(idx) => "local.set \{idx}"
    LocalTee(idx) => "local.tee \{idx}"
    GlobalGet(idx) => "global.get \{idx}"
    GlobalSet(idx) => "global.set \{idx}"
    TableGet(idx) => if idx == 0 { "table.get" } else { "table.get \{idx}" }
    TableSet(idx) => if idx == 0 { "table.set" } else { "table.set \{idx}" }
    TableSize(idx) => if idx == 0 { "table.size" } else { "table.size \{idx}" }
    TableGrow(idx) => if idx == 0 { "table.grow" } else { "table.grow \{idx}" }
    TableFill(idx) => if idx == 0 { "table.fill" } else { "table.fill \{idx}" }
    TableCopy(dst, src) => "table.copy \{dst} \{src}"
    TableInit(table_idx, elem_idx) => "table.init \{table_idx} \{elem_idx}"
    I32Load(mem, align, offset) => mem_instr("i32.load", mem, align, offset, 2)
    I64Load(mem, align, offset) => mem_instr("i64.load", mem, align, offset, 3)
    F32Load(mem, align, offset) => mem_instr("f32.load", mem, align, offset, 2)
    F64Load(mem, align, offset) => mem_instr("f64.load", mem, align, offset, 3)
    I32Load8S(mem, align, offset) =>
      mem_instr("i32.load8_s", mem, align, offset, 0)
    I32Load8U(mem, align, offset) =>
      mem_instr("i32.load8_u", mem, align, offset, 0)
    I32Load16S(mem, align, offset) =>
      mem_instr("i32.load16_s", mem, align, offset, 1)
    I32Load16U(mem, align, offset) =>
      mem_instr("i32.load16_u", mem, align, offset, 1)
    I64Load8S(mem, align, offset) =>
      mem_instr("i64.load8_s", mem, align, offset, 0)
    I64Load8U(mem, align, offset) =>
      mem_instr("i64.load8_u", mem, align, offset, 0)
    I64Load16S(mem, align, offset) =>
      mem_instr("i64.load16_s", mem, align, offset, 1)
    I64Load16U(mem, align, offset) =>
      mem_instr("i64.load16_u", mem, align, offset, 1)
    I64Load32S(mem, align, offset) =>
      mem_instr("i64.load32_s", mem, align, offset, 2)
    I64Load32U(mem, align, offset) =>
      mem_instr("i64.load32_u", mem, align, offset, 2)
    I32Store(mem, align, offset) =>
      mem_instr("i32.store", mem, align, offset, 2)
    I64Store(mem, align, offset) =>
      mem_instr("i64.store", mem, align, offset, 3)
    F32Store(mem, align, offset) =>
      mem_instr("f32.store", mem, align, offset, 2)
    F64Store(mem, align, offset) =>
      mem_instr("f64.store", mem, align, offset, 3)
    I32Store8(mem, align, offset) =>
      mem_instr("i32.store8", mem, align, offset, 0)
    I32Store16(mem, align, offset) =>
      mem_instr("i32.store16", mem, align, offset, 1)
    I64Store8(mem, align, offset) =>
      mem_instr("i64.store8", mem, align, offset, 0)
    I64Store16(mem, align, offset) =>
      mem_instr("i64.store16", mem, align, offset, 1)
    I64Store32(mem, align, offset) =>
      mem_instr("i64.store32", mem, align, offset, 2)
    MemorySize(mem) =>
      if mem == 0 {
        "memory.size"
      } else {
        "memory.size \{mem}"
      }
    MemoryGrow(mem) =>
      if mem == 0 {
        "memory.grow"
      } else {
        "memory.grow \{mem}"
      }
    MemoryInit(mem, data) => "memory.init \{mem} \{data}"
    DataDrop(idx) => "data.drop \{idx}"
    MemoryCopy(dst, src) => "memory.copy \{dst} \{src}"
    MemoryFill(mem) =>
      if mem == 0 {
        "memory.fill"
      } else {
        "memory.fill \{mem}"
      }
    ElemDrop(idx) => "elem.drop \{idx}"
    Atomic(subop, mem, align, offset) => atomic_instr(subop, mem, align, offset)
    RefNull(t) => "ref.null \{ref_type_to_wat(t)}"
    RefIsNull => "ref.is_null"
    RefFunc(idx) => "ref.func \{idx}"
    RefAsNonNull => "ref.as_non_null"
    RefEqInstr => "ref.eq"
    BrOnNull(idx) => "br_on_null \{idx}"
    BrOnNonNull(idx) => "br_on_non_null \{idx}"
    I32Const(v) => "i32.const \{v}"
    I64Const(v) => "i64.const \{v}"
    F32Const(v) => "f32.const \{v}"
    F64Const(v) => "f64.const \{v}"
    I32Eqz => "i32.eqz"
    I32Eq => "i32.eq"
    I32Ne => "i32.ne"
    I32LtS => "i32.lt_s"
    I32LtU => "i32.lt_u"
    I32GtS => "i32.gt_s"
    I32GtU => "i32.gt_u"
    I32LeS => "i32.le_s"
    I32LeU => "i32.le_u"
    I32GeS => "i32.ge_s"
    I32GeU => "i32.ge_u"
    I32Clz => "i32.clz"
    I32Ctz => "i32.ctz"
    I32Popcnt => "i32.popcnt"
    I32Add => "i32.add"
    I32Sub => "i32.sub"
    I32Mul => "i32.mul"
    I32DivS => "i32.div_s"
    I32DivU => "i32.div_u"
    I32RemS => "i32.rem_s"
    I32RemU => "i32.rem_u"
    I32And => "i32.and"
    I32Or => "i32.or"
    I32Xor => "i32.xor"
    I32Shl => "i32.shl"
    I32ShrS => "i32.shr_s"
    I32ShrU => "i32.shr_u"
    I32Rotl => "i32.rotl"
    I32Rotr => "i32.rotr"
    I32Extend8S => "i32.extend8_s"
    I32Extend16S => "i32.extend16_s"
    I64Eqz => "i64.eqz"
    I64Eq => "i64.eq"
    I64Ne => "i64.ne"
    I64LtS => "i64.lt_s"
    I64LtU => "i64.lt_u"
    I64GtS => "i64.gt_s"
    I64GtU => "i64.gt_u"
    I64LeS => "i64.le_s"
    I64LeU => "i64.le_u"
    I64GeS => "i64.ge_s"
    I64GeU => "i64.ge_u"
    I64Clz => "i64.clz"
    I64Ctz => "i64.ctz"
    I64Popcnt => "i64.popcnt"
    I64Add => "i64.add"
    I64Sub => "i64.sub"
    I64Mul => "i64.mul"
    I64MulWideS => "i64.mul_wide_s"
    I64MulWideU => "i64.mul_wide_u"
    I64DivS => "i64.div_s"
    I64DivU => "i64.div_u"
    I64RemS => "i64.rem_s"
    I64RemU => "i64.rem_u"
    I64And => "i64.and"
    I64Or => "i64.or"
    I64Xor => "i64.xor"
    I64Shl => "i64.shl"
    I64ShrS => "i64.shr_s"
    I64ShrU => "i64.shr_u"
    I64Rotl => "i64.rotl"
    I64Rotr => "i64.rotr"
    I64Extend8S => "i64.extend8_s"
    I64Extend16S => "i64.extend16_s"
    I64Extend32S => "i64.extend32_s"
    F32Eq => "f32.eq"
    F32Ne => "f32.ne"
    F32Lt => "f32.lt"
    F32Gt => "f32.gt"
    F32Le => "f32.le"
    F32Ge => "f32.ge"
    F32Abs => "f32.abs"
    F32Neg => "f32.neg"
    F32Ceil => "f32.ceil"
    F32Floor => "f32.floor"
    F32Trunc => "f32.trunc"
    F32Nearest => "f32.nearest"
    F32Sqrt => "f32.sqrt"
    F32Add => "f32.add"
    F32Sub => "f32.sub"
    F32Mul => "f32.mul"
    F32Div => "f32.div"
    F32Min => "f32.min"
    F32Max => "f32.max"
    F32Copysign => "f32.copysign"
    F64Eq => "f64.eq"
    F64Ne => "f64.ne"
    F64Lt => "f64.lt"
    F64Gt => "f64.gt"
    F64Le => "f64.le"
    F64Ge => "f64.ge"
    F64Abs => "f64.abs"
    F64Neg => "f64.neg"
    F64Ceil => "f64.ceil"
    F64Floor => "f64.floor"
    F64Trunc => "f64.trunc"
    F64Nearest => "f64.nearest"
    F64Sqrt => "f64.sqrt"
    F64Add => "f64.add"
    F64Sub => "f64.sub"
    F64Mul => "f64.mul"
    F64Div => "f64.div"
    F64Min => "f64.min"
    F64Max => "f64.max"
    F64Copysign => "f64.copysign"
    I32WrapI64 => "i32.wrap_i64"
    I32TruncF32S => "i32.trunc_f32_s"
    I32TruncF32U => "i32.trunc_f32_u"
    I32TruncF64S => "i32.trunc_f64_s"
    I32TruncF64U => "i32.trunc_f64_u"
    I64ExtendI32S => "i64.extend_i32_s"
    I64ExtendI32U => "i64.extend_i32_u"
    I64TruncF32S => "i64.trunc_f32_s"
    I64TruncF32U => "i64.trunc_f32_u"
    I64TruncF64S => "i64.trunc_f64_s"
    I64TruncF64U => "i64.trunc_f64_u"
    F32ConvertI32S => "f32.convert_i32_s"
    F32ConvertI32U => "f32.convert_i32_u"
    F32ConvertI64S => "f32.convert_i64_s"
    F32ConvertI64U => "f32.convert_i64_u"
    F32DemoteF64 => "f32.demote_f64"
    F64ConvertI32S => "f64.convert_i32_s"
    F64ConvertI32U => "f64.convert_i32_u"
    F64ConvertI64S => "f64.convert_i64_s"
    F64ConvertI64U => "f64.convert_i64_u"
    F64PromoteF32 => "f64.promote_f32"
    I32ReinterpretF32 => "i32.reinterpret_f32"
    I64ReinterpretF64 => "i64.reinterpret_f64"
    F32ReinterpretI32 => "f32.reinterpret_i32"
    F64ReinterpretI64 => "f64.reinterpret_i64"
    I32TruncSatF32S => "i32.trunc_sat_f32_s"
    I32TruncSatF32U => "i32.trunc_sat_f32_u"
    I32TruncSatF64S => "i32.trunc_sat_f64_s"
    I32TruncSatF64U => "i32.trunc_sat_f64_u"
    I64TruncSatF32S => "i64.trunc_sat_f32_s"
    I64TruncSatF32U => "i64.trunc_sat_f32_u"
    I64TruncSatF64S => "i64.trunc_sat_f64_s"
    I64TruncSatF64U => "i64.trunc_sat_f64_u"
    StructNew(idx) => "struct.new \{idx}"
    StructNewDefault(idx) => "struct.new_default \{idx}"
    StructGet(type_idx, field_idx) => "struct.get \{type_idx} \{field_idx}"
    StructGetS(type_idx, field_idx) => "struct.get_s \{type_idx} \{field_idx}"
    StructGetU(type_idx, field_idx) => "struct.get_u \{type_idx} \{field_idx}"
    StructSet(type_idx, field_idx) => "struct.set \{type_idx} \{field_idx}"
    ArrayNew(idx) => "array.new \{idx}"
    ArrayNewDefault(idx) => "array.new_default \{idx}"
    ArrayNewFixed(type_idx, len) => "array.new_fixed \{type_idx} \{len}"
    ArrayNewData(type_idx, data_idx) => "array.new_data \{type_idx} \{data_idx}"
    ArrayNewElem(type_idx, elem_idx) => "array.new_elem \{type_idx} \{elem_idx}"
    ArrayGet(idx) => "array.get \{idx}"
    ArrayGetS(idx) => "array.get_s \{idx}"
    ArrayGetU(idx) => "array.get_u \{idx}"
    ArraySet(idx) => "array.set \{idx}"
    ArrayLen => "array.len"
    ArrayFill(idx) => "array.fill \{idx}"
    ArrayCopy(dst, src) => "array.copy \{dst} \{src}"
    ArrayInitData(type_idx, data_idx) =>
      "array.init_data \{type_idx} \{data_idx}"
    ArrayInitElem(type_idx, elem_idx) =>
      "array.init_elem \{type_idx} \{elem_idx}"
    RefTest(t) => "ref.test \{ref_type_to_wat(t)}"
    RefTestNull(t) => "ref.test (ref null \{heap_type_to_wat(t)})"
    RefCast(t) => "ref.cast \{ref_type_to_wat(t)}"
    RefCastNull(t) => "ref.cast (ref null \{heap_type_to_wat(t)})"
    BrOnCast(label, from, to) =>
      "br_on_cast \{label} \{ref_type_to_wat(from)} \{ref_type_to_wat(to)}"
    BrOnCastFail(label, from, to) =>
      "br_on_cast_fail \{label} \{ref_type_to_wat(from)} \{ref_type_to_wat(to)}"
    RefI31 => "ref.i31"
    I31GetS => "i31.get_s"
    I31GetU => "i31.get_u"
    AnyConvertExtern => "any.convert_extern"
    ExternConvertAny => "extern.convert_any"
    V128Const(bytes) => "v128.const i8x16 \{format_v128_bytes(bytes)}"
    V128Load(mem, align, offset) =>
      mem_instr("v128.load", mem, align, offset, 4)
    V128Load8x8S(mem, align, offset) =>
      mem_instr("v128.load8x8_s", mem, align, offset, 3)
    V128Load8x8U(mem, align, offset) =>
      mem_instr("v128.load8x8_u", mem, align, offset, 3)
    V128Load16x4S(mem, align, offset) =>
      mem_instr("v128.load16x4_s", mem, align, offset, 3)
    V128Load16x4U(mem, align, offset) =>
      mem_instr("v128.load16x4_u", mem, align, offset, 3)
    V128Load32x2S(mem, align, offset) =>
      mem_instr("v128.load32x2_s", mem, align, offset, 3)
    V128Load32x2U(mem, align, offset) =>
      mem_instr("v128.load32x2_u", mem, align, offset, 3)
    V128Load8Splat(mem, align, offset) =>
      mem_instr("v128.load8_splat", mem, align, offset, 0)
    V128Load16Splat(mem, align, offset) =>
      mem_instr("v128.load16_splat", mem, align, offset, 1)
    V128Load32Splat(mem, align, offset) =>
      mem_instr("v128.load32_splat", mem, align, offset, 2)
    V128Load64Splat(mem, align, offset) =>
      mem_instr("v128.load64_splat", mem, align, offset, 3)
    V128Load32Zero(mem, align, offset) =>
      mem_instr("v128.load32_zero", mem, align, offset, 2)
    V128Load64Zero(mem, align, offset) =>
      mem_instr("v128.load64_zero", mem, align, offset, 3)
    V128Store(mem, align, offset) =>
      mem_instr("v128.store", mem, align, offset, 4)
    V128Load8Lane(mem, align, offset, lane) => {
      let base = mem_instr("v128.load8_lane", mem, align, offset, 0)
      "\{base} \{lane}"
    }
    V128Load16Lane(mem, align, offset, lane) => {
      let base = mem_instr("v128.load16_lane", mem, align, offset, 1)
      "\{base} \{lane}"
    }
    V128Load32Lane(mem, align, offset, lane) => {
      let base = mem_instr("v128.load32_lane", mem, align, offset, 2)
      "\{base} \{lane}"
    }
    V128Load64Lane(mem, align, offset, lane) => {
      let base = mem_instr("v128.load64_lane", mem, align, offset, 3)
      "\{base} \{lane}"
    }
    V128Store8Lane(mem, align, offset, lane) => {
      let base = mem_instr("v128.store8_lane", mem, align, offset, 0)
      "\{base} \{lane}"
    }
    V128Store16Lane(mem, align, offset, lane) => {
      let base = mem_instr("v128.store16_lane", mem, align, offset, 1)
      "\{base} \{lane}"
    }
    V128Store32Lane(mem, align, offset, lane) => {
      let base = mem_instr("v128.store32_lane", mem, align, offset, 2)
      "\{base} \{lane}"
    }
    V128Store64Lane(mem, align, offset, lane) => {
      let base = mem_instr("v128.store64_lane", mem, align, offset, 3)
      "\{base} \{lane}"
    }
    I8x16Shuffle(lanes) => {
      let lanes_str = lanes
        .iter()
        .map(fn(l) { l.to_string() })
        .collect()
        .join(" ")
      "i8x16.shuffle \{lanes_str}"
    }
    I8x16Swizzle => "i8x16.swizzle"
    I8x16Splat => "i8x16.splat"
    I16x8Splat => "i16x8.splat"
    I32x4Splat => "i32x4.splat"
    I64x2Splat => "i64x2.splat"
    F32x4Splat => "f32x4.splat"
    F64x2Splat => "f64x2.splat"
    I8x16ExtractLaneS(lane) => "i8x16.extract_lane_s \{lane}"
    I8x16ExtractLaneU(lane) => "i8x16.extract_lane_u \{lane}"
    I16x8ExtractLaneS(lane) => "i16x8.extract_lane_s \{lane}"
    I16x8ExtractLaneU(lane) => "i16x8.extract_lane_u \{lane}"
    I32x4ExtractLane(lane) => "i32x4.extract_lane \{lane}"
    I64x2ExtractLane(lane) => "i64x2.extract_lane \{lane}"
    F32x4ExtractLane(lane) => "f32x4.extract_lane \{lane}"
    F64x2ExtractLane(lane) => "f64x2.extract_lane \{lane}"
    I8x16ReplaceLane(lane) => "i8x16.replace_lane \{lane}"
    I16x8ReplaceLane(lane) => "i16x8.replace_lane \{lane}"
    I32x4ReplaceLane(lane) => "i32x4.replace_lane \{lane}"
    I64x2ReplaceLane(lane) => "i64x2.replace_lane \{lane}"
    F32x4ReplaceLane(lane) => "f32x4.replace_lane \{lane}"
    F64x2ReplaceLane(lane) => "f64x2.replace_lane \{lane}"
    I8x16Eq => "i8x16.eq"
    I8x16Ne => "i8x16.ne"
    I8x16LtS => "i8x16.lt_s"
    I8x16LtU => "i8x16.lt_u"
    I8x16GtS => "i8x16.gt_s"
    I8x16GtU => "i8x16.gt_u"
    I8x16LeS => "i8x16.le_s"
    I8x16LeU => "i8x16.le_u"
    I8x16GeS => "i8x16.ge_s"
    I8x16GeU => "i8x16.ge_u"
    I16x8Eq => "i16x8.eq"
    I16x8Ne => "i16x8.ne"
    I16x8LtS => "i16x8.lt_s"
    I16x8LtU => "i16x8.lt_u"
    I16x8GtS => "i16x8.gt_s"
    I16x8GtU => "i16x8.gt_u"
    I16x8LeS => "i16x8.le_s"
    I16x8LeU => "i16x8.le_u"
    I16x8GeS => "i16x8.ge_s"
    I16x8GeU => "i16x8.ge_u"
    I32x4Eq => "i32x4.eq"
    I32x4Ne => "i32x4.ne"
    I32x4LtS => "i32x4.lt_s"
    I32x4LtU => "i32x4.lt_u"
    I32x4GtS => "i32x4.gt_s"
    I32x4GtU => "i32x4.gt_u"
    I32x4LeS => "i32x4.le_s"
    I32x4LeU => "i32x4.le_u"
    I32x4GeS => "i32x4.ge_s"
    I32x4GeU => "i32x4.ge_u"
    I64x2Eq => "i64x2.eq"
    I64x2Ne => "i64x2.ne"
    I64x2LtS => "i64x2.lt_s"
    I64x2GtS => "i64x2.gt_s"
    I64x2LeS => "i64x2.le_s"
    I64x2GeS => "i64x2.ge_s"
    F32x4Eq => "f32x4.eq"
    F32x4Ne => "f32x4.ne"
    F32x4Lt => "f32x4.lt"
    F32x4Gt => "f32x4.gt"
    F32x4Le => "f32x4.le"
    F32x4Ge => "f32x4.ge"
    F64x2Eq => "f64x2.eq"
    F64x2Ne => "f64x2.ne"
    F64x2Lt => "f64x2.lt"
    F64x2Gt => "f64x2.gt"
    F64x2Le => "f64x2.le"
    F64x2Ge => "f64x2.ge"
    V128Not => "v128.not"
    V128And => "v128.and"
    V128AndNot => "v128.andnot"
    V128Or => "v128.or"
    V128Xor => "v128.xor"
    V128Bitselect => "v128.bitselect"
    V128AnyTrue => "v128.any_true"
    I8x16Abs => "i8x16.abs"
    I8x16Neg => "i8x16.neg"
    I8x16Popcnt => "i8x16.popcnt"
    I8x16AllTrue => "i8x16.all_true"
    I8x16Bitmask => "i8x16.bitmask"
    I8x16NarrowI16x8S => "i8x16.narrow_i16x8_s"
    I8x16NarrowI16x8U => "i8x16.narrow_i16x8_u"
    I8x16Shl => "i8x16.shl"
    I8x16ShrS => "i8x16.shr_s"
    I8x16ShrU => "i8x16.shr_u"
    I8x16Add => "i8x16.add"
    I8x16AddSatS => "i8x16.add_sat_s"
    I8x16AddSatU => "i8x16.add_sat_u"
    I8x16Sub => "i8x16.sub"
    I8x16SubSatS => "i8x16.sub_sat_s"
    I8x16SubSatU => "i8x16.sub_sat_u"
    I8x16MinS => "i8x16.min_s"
    I8x16MinU => "i8x16.min_u"
    I8x16MaxS => "i8x16.max_s"
    I8x16MaxU => "i8x16.max_u"
    I8x16AvgrU => "i8x16.avgr_u"
    I16x8ExtAddPairwiseI8x16S => "i16x8.extadd_pairwise_i8x16_s"
    I16x8ExtAddPairwiseI8x16U => "i16x8.extadd_pairwise_i8x16_u"
    I16x8Abs => "i16x8.abs"
    I16x8Neg => "i16x8.neg"
    I16x8Q15MulrSatS => "i16x8.q15mulr_sat_s"
    I16x8AllTrue => "i16x8.all_true"
    I16x8Bitmask => "i16x8.bitmask"
    I16x8NarrowI32x4S => "i16x8.narrow_i32x4_s"
    I16x8NarrowI32x4U => "i16x8.narrow_i32x4_u"
    I16x8ExtendLowI8x16S => "i16x8.extend_low_i8x16_s"
    I16x8ExtendHighI8x16S => "i16x8.extend_high_i8x16_s"
    I16x8ExtendLowI8x16U => "i16x8.extend_low_i8x16_u"
    I16x8ExtendHighI8x16U => "i16x8.extend_high_i8x16_u"
    I16x8Shl => "i16x8.shl"
    I16x8ShrS => "i16x8.shr_s"
    I16x8ShrU => "i16x8.shr_u"
    I16x8Add => "i16x8.add"
    I16x8AddSatS => "i16x8.add_sat_s"
    I16x8AddSatU => "i16x8.add_sat_u"
    I16x8Sub => "i16x8.sub"
    I16x8SubSatS => "i16x8.sub_sat_s"
    I16x8SubSatU => "i16x8.sub_sat_u"
    I16x8Mul => "i16x8.mul"
    I16x8MinS => "i16x8.min_s"
    I16x8MinU => "i16x8.min_u"
    I16x8MaxS => "i16x8.max_s"
    I16x8MaxU => "i16x8.max_u"
    I16x8AvgrU => "i16x8.avgr_u"
    I16x8ExtMulLowI8x16S => "i16x8.extmul_low_i8x16_s"
    I16x8ExtMulHighI8x16S => "i16x8.extmul_high_i8x16_s"
    I16x8ExtMulLowI8x16U => "i16x8.extmul_low_i8x16_u"
    I16x8ExtMulHighI8x16U => "i16x8.extmul_high_i8x16_u"
    I32x4ExtAddPairwiseI16x8S => "i32x4.extadd_pairwise_i16x8_s"
    I32x4ExtAddPairwiseI16x8U => "i32x4.extadd_pairwise_i16x8_u"
    I32x4Abs => "i32x4.abs"
    I32x4Neg => "i32x4.neg"
    I32x4AllTrue => "i32x4.all_true"
    I32x4Bitmask => "i32x4.bitmask"
    I32x4ExtendLowI16x8S => "i32x4.extend_low_i16x8_s"
    I32x4ExtendHighI16x8S => "i32x4.extend_high_i16x8_s"
    I32x4ExtendLowI16x8U => "i32x4.extend_low_i16x8_u"
    I32x4ExtendHighI16x8U => "i32x4.extend_high_i16x8_u"
    I32x4Shl => "i32x4.shl"
    I32x4ShrS => "i32x4.shr_s"
    I32x4ShrU => "i32x4.shr_u"
    I32x4Add => "i32x4.add"
    I32x4Sub => "i32x4.sub"
    I32x4Mul => "i32x4.mul"
    I32x4MinS => "i32x4.min_s"
    I32x4MinU => "i32x4.min_u"
    I32x4MaxS => "i32x4.max_s"
    I32x4MaxU => "i32x4.max_u"
    I32x4DotI16x8S => "i32x4.dot_i16x8_s"
    I32x4ExtMulLowI16x8S => "i32x4.extmul_low_i16x8_s"
    I32x4ExtMulHighI16x8S => "i32x4.extmul_high_i16x8_s"
    I32x4ExtMulLowI16x8U => "i32x4.extmul_low_i16x8_u"
    I32x4ExtMulHighI16x8U => "i32x4.extmul_high_i16x8_u"
    I64x2Abs => "i64x2.abs"
    I64x2Neg => "i64x2.neg"
    I64x2AllTrue => "i64x2.all_true"
    I64x2Bitmask => "i64x2.bitmask"
    I64x2ExtendLowI32x4S => "i64x2.extend_low_i32x4_s"
    I64x2ExtendHighI32x4S => "i64x2.extend_high_i32x4_s"
    I64x2ExtendLowI32x4U => "i64x2.extend_low_i32x4_u"
    I64x2ExtendHighI32x4U => "i64x2.extend_high_i32x4_u"
    I64x2Shl => "i64x2.shl"
    I64x2ShrS => "i64x2.shr_s"
    I64x2ShrU => "i64x2.shr_u"
    I64x2Add => "i64x2.add"
    I64x2Sub => "i64x2.sub"
    I64x2Mul => "i64x2.mul"
    I64x2ExtMulLowI32x4S => "i64x2.extmul_low_i32x4_s"
    I64x2ExtMulHighI32x4S => "i64x2.extmul_high_i32x4_s"
    I64x2ExtMulLowI32x4U => "i64x2.extmul_low_i32x4_u"
    I64x2ExtMulHighI32x4U => "i64x2.extmul_high_i32x4_u"
    F32x4Ceil => "f32x4.ceil"
    F32x4Floor => "f32x4.floor"
    F32x4Trunc => "f32x4.trunc"
    F32x4Nearest => "f32x4.nearest"
    F32x4Abs => "f32x4.abs"
    F32x4Neg => "f32x4.neg"
    F32x4Sqrt => "f32x4.sqrt"
    F32x4Add => "f32x4.add"
    F32x4Sub => "f32x4.sub"
    F32x4Mul => "f32x4.mul"
    F32x4Div => "f32x4.div"
    F32x4Min => "f32x4.min"
    F32x4Max => "f32x4.max"
    F32x4Pmin => "f32x4.pmin"
    F32x4Pmax => "f32x4.pmax"
    F64x2Ceil => "f64x2.ceil"
    F64x2Floor => "f64x2.floor"
    F64x2Trunc => "f64x2.trunc"
    F64x2Nearest => "f64x2.nearest"
    F64x2Abs => "f64x2.abs"
    F64x2Neg => "f64x2.neg"
    F64x2Sqrt => "f64x2.sqrt"
    F64x2Add => "f64x2.add"
    F64x2Sub => "f64x2.sub"
    F64x2Mul => "f64x2.mul"
    F64x2Div => "f64x2.div"
    F64x2Min => "f64x2.min"
    F64x2Max => "f64x2.max"
    F64x2Pmin => "f64x2.pmin"
    F64x2Pmax => "f64x2.pmax"
    I32x4TruncSatF32x4S => "i32x4.trunc_sat_f32x4_s"
    I32x4TruncSatF32x4U => "i32x4.trunc_sat_f32x4_u"
    F32x4ConvertI32x4S => "f32x4.convert_i32x4_s"
    F32x4ConvertI32x4U => "f32x4.convert_i32x4_u"
    I32x4TruncSatF64x2SZero => "i32x4.trunc_sat_f64x2_s_zero"
    I32x4TruncSatF64x2UZero => "i32x4.trunc_sat_f64x2_u_zero"
    F64x2ConvertLowI32x4S => "f64x2.convert_low_i32x4_s"
    F64x2ConvertLowI32x4U => "f64x2.convert_low_i32x4_u"
    F32x4DemoteF64x2Zero => "f32x4.demote_f64x2_zero"
    F64x2PromoteLowF32x4 => "f64x2.promote_low_f32x4"
    I8x16RelaxedSwizzle => "i8x16.relaxed_swizzle"
    I32x4RelaxedTruncF32x4S => "i32x4.relaxed_trunc_f32x4_s"
    I32x4RelaxedTruncF32x4U => "i32x4.relaxed_trunc_f32x4_u"
    I32x4RelaxedTruncF64x2SZero => "i32x4.relaxed_trunc_f64x2_s_zero"
    I32x4RelaxedTruncF64x2UZero => "i32x4.relaxed_trunc_f64x2_u_zero"
    F32x4RelaxedMadd => "f32x4.relaxed_madd"
    F32x4RelaxedNmadd => "f32x4.relaxed_nmadd"
    F64x2RelaxedMadd => "f64x2.relaxed_madd"
    F64x2RelaxedNmadd => "f64x2.relaxed_nmadd"
    I8x16RelaxedLaneselect => "i8x16.relaxed_laneselect"
    I16x8RelaxedLaneselect => "i16x8.relaxed_laneselect"
    I32x4RelaxedLaneselect => "i32x4.relaxed_laneselect"
    I64x2RelaxedLaneselect => "i64x2.relaxed_laneselect"
    F32x4RelaxedMin => "f32x4.relaxed_min"
    F32x4RelaxedMax => "f32x4.relaxed_max"
    F64x2RelaxedMin => "f64x2.relaxed_min"
    F64x2RelaxedMax => "f64x2.relaxed_max"
    I16x8RelaxedQ15mulrS => "i16x8.relaxed_q15mulr_s"
    I16x8RelaxedDotI8x16I7x16S => "i16x8.relaxed_dot_i8x16_i7x16_s"
    I32x4RelaxedDotI8x16I7x16AddS => "i32x4.relaxed_dot_i8x16_i7x16_add_s"
  }
}
