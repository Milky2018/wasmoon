// ============================================================
// Value Type Parsing
// ============================================================

///|
fn Parser::resolve_heap_type_as_ref_value_type(
  self : Parser,
  heap_type : Int,
  nullable : Bool,
) -> @types.ValueType raise ParserError {
  fn resolve_typed_ref(
    type_idx : Int,
    nullable : Bool,
  ) -> @types.ValueType raise ParserError {
    if type_idx < 0 || type_idx >= self.types.length() {
      raise ParseError("invalid heap type")
    }
    match self.types[type_idx].composite {
      Func(_) =>
        if nullable {
          RefNullFuncTyped(type_idx)
        } else {
          RefFuncTyped(type_idx)
        }
      Struct(_) =>
        if nullable {
          RefNullStruct(type_idx)
        } else {
          RefStruct(type_idx)
        }
      Array(_) =>
        if nullable {
          RefNullArray(type_idx)
        } else {
          RefArray(type_idx)
        }
    }
  }

  fn resolve_abstract_heap(
    heap_type : Int,
    nullable : Bool,
  ) -> @types.ValueType raise ParserError {
    match heap_type {
      -16 => if nullable { FuncRef } else { RefFunc }
      -17 => if nullable { ExternRef } else { RefExtern }
      -18 => if nullable { AnyRef } else { RefAny }
      -19 => if nullable { RefNullEq } else { RefEq }
      -20 => if nullable { RefNullI31 } else { RefI31 }
      -21 => if nullable { StructRef } else { RefStructAbs }
      -22 => if nullable { ArrayRef } else { RefArrayAbs }
      -23 => ExnRef
      -15 => if nullable { NullRef } else { RefNone }
      -14 => NullExternRef
      -13 => NullFuncRef
      -12 => NullExnRef
      _ => raise ParseError("invalid heap type")
    }
  }

  if heap_type < 0 {
    resolve_abstract_heap(heap_type, nullable)
  } else {
    resolve_typed_ref(heap_type, nullable)
  }
}

///|
fn Parser::read_value_type(self : Parser) -> @types.ValueType raise ParserError {
  fn resolve_typed_ref(
    type_idx : Int,
    nullable : Bool,
  ) -> @types.ValueType raise ParserError {
    self.resolve_heap_type_as_ref_value_type(type_idx, nullable)
  }

  fn resolve_abstract_heap(
    heap_type : Int,
    nullable : Bool,
  ) -> @types.ValueType raise ParserError {
    self.resolve_heap_type_as_ref_value_type(heap_type, nullable)
  }

  let byte = self.read_byte()
  match byte {
    0x7F => I32
    0x7E => I64
    0x7D => F32
    0x7C => F64
    0x7B => V128

    // Reference shorthands
    0x70 => FuncRef
    0x6F => ExternRef
    0x6E => AnyRef
    0x6D => RefNullEq
    0x6C => RefNullI31
    0x6B => StructRef
    0x6A => ArrayRef
    0x69 => ExnRef
    0x71 => NullRef
    0x72 => NullExternRef
    0x73 => NullFuncRef
    0x74 => NullExnRef

    // ref heaptype
    0x64 => {
      let heap_type = self.read_heap_type()
      if heap_type < 0 {
        resolve_abstract_heap(heap_type, false)
      } else {
        resolve_typed_ref(heap_type, false)
      }
    }

    // ref shared heaptype (shared reference types proposal)
    0x65 => {
      self.read_heap_type() |> ignore
      raise ParseError("shared reference types not supported")
    }

    // ref null shared heaptype (shared reference types proposal)
    0x62 => {
      self.read_heap_type() |> ignore
      raise ParseError("shared reference types not supported")
    }

    // ref null heaptype
    0x63 => {
      let heap_type = self.read_heap_type()
      if heap_type < 0 {
        resolve_abstract_heap(heap_type, true)
      } else {
        resolve_typed_ref(heap_type, true)
      }
    }
    _ => raise InvalidValueType(byte)
  }
}

///|
/// Read a heap type (signed LEB128 type index or abstract heap type)
fn Parser::read_heap_type(self : Parser) -> Int raise ParserError {
  // Heap types are encoded as signed LEB128
  // Negative values represent abstract heap types:
  //   -0x10 (0x70) = func
  //   -0x11 (0x6F) = extern
  // Positive values represent type indices
  self.read_i32()
}

///|
/// Read block type (uses peek to avoid rewind)
fn Parser::read_block_type(self : Parser) -> @types.BlockType raise ParserError {
  let byte = self.peek_byte()
  match byte {
    0x40 => {
      self.skip(1)
      Empty
    }
    0x7F
    | 0x7E
    | 0x7D
    | 0x7C
    | 0x7B
    | 0x70
    | 0x6F
    | 0x6E
    | 0x6D
    | 0x6C
    | 0x6B
    | 0x6A
    | 0x69
    | 0x71
    | 0x72
    | 0x73
    | 0x74
    | 0x64
    | 0x65
    | 0x63
    | 0x62 => Value(self.read_value_type())
    _ => TypeIndex(self.read_i32())
  }
}
