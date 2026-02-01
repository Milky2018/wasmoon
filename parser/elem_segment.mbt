// ============================================================
// Element Segment Parsing
// ============================================================

///|
/// Read element segment based on flags
/// Returns (mode, elem_type, init_exprs)
fn Parser::read_elem_segment(
  self : Parser,
  flags : Int,
) -> (@types.ElemMode, @types.ValueType, Array[Array[@types.Instruction]]) raise ParserError {
  // Flags encoding:
  // bit 0: 0 = active, 1 = passive/declarative
  // bit 1: 0 = implicit table 0, 1 = explicit table index (only if active)
  // bit 2: 0 = func indices, 1 = expressions
  // For passive: bit 1 distinguishes passive (0) from declarative (1)
  let is_passive_or_declarative = (flags & 0x01) != 0
  let has_table_index_or_is_declarative = (flags & 0x02) != 0
  let uses_expressions = (flags & 0x04) != 0
  let mode : @types.ElemMode = if is_passive_or_declarative {
    if has_table_index_or_is_declarative {
      @types.ElemMode::Declarative
    } else {
      @types.ElemMode::Passive
    }
  } else {
    // Active segment
    let table_idx = if has_table_index_or_is_declarative {
      self.read_u32()
    } else {
      0
    }
    let offset = self.read_expr()
    @types.ElemMode::Active(table_idx, offset)
  }

  // Read element type
  // flags encoding for elem type:
  // - flags 0, 4: no elemkind/reftype (implicit funcref)
  // - flags 1, 2, 3: has elemkind byte (0x00 = funcref)
  // - flags 5, 6, 7: has reftype byte (0x70=funcref, 0x6F=externref, etc.)
  // Note: flags 4 uses expressions but has NO reftype byte (implicit funcref)
  let has_elemkind = flags == 1 || flags == 2 || flags == 3
  let has_reftype = flags == 5 || flags == 6 || flags == 7
  let elem_type : @types.ValueType = if has_reftype {
    // flags 5, 6, 7: has explicit reftype
    let vt = self.read_value_type()
    match vt {
      I32 | I64 | F32 | F64 | V128 => raise MalformedReferenceType(0)
      _ => vt
    }
  } else if has_elemkind {
    // flags 1, 2, 3: has elemkind
    let kind = self.read_byte()
    if kind != 0x00 {
      raise ParseError("unsupported element kind: \{kind}")
    }
    @types.ValueType::FuncRef
  } else {
    // flags 0: no elemkind, implicit funcref
    @types.ValueType::FuncRef
  }

  // Read init expressions or function indices
  let elem_count = self.read_u32()
  let init : Array[Array[@types.Instruction]] = []
  for _ in 0..<elem_count {
    if uses_expressions {
      // Read expression
      init.push(self.read_expr())
    } else {
      // Read function index, convert to ref.func expression
      let func_idx = self.read_u32()
      init.push([@types.Instruction::RefFunc(func_idx)])
    }
  }
  (mode, elem_type, init)
}
