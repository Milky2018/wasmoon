///|
/// Parsing for component type section (section 7 in the component binary format).
///
/// For now, this only supports a small subset (primvaltype + basic functype)
/// to unblock end-to-end parsing and testing.

///|
pub(all) enum PrimValType {
  Bool
  S8
  U8
  S16
  U16
  S32
  U32
  S64
  U64
  F32
  F64
  Char
  String
  ErrorContext
} derive(Show, Eq)

///|
pub(all) enum ValType {
  TypeIdx(Int)
  Prim(PrimValType)
} derive(Show, Eq)

///|
pub(all) struct Param {
  label : String
  ty : ValType
} derive(Show, Eq)

///|
pub(all) struct FuncType {
  is_async : Bool
  params : Array[Param]
  result : ValType?
} derive(Show, Eq)

///|
pub(all) enum TypeDef {
  DefValType(PrimValType)
  FuncType(FuncType)
  ComponentTypeEmpty
  InstanceTypeEmpty
} derive(Show, Eq)

///|
fn Reader::peek_u8(self : Reader) -> Int raise ComponentParseError {
  if self.pos >= self.data.length() {
    raise UnexpectedEndOfInput
  }
  self.data[self.pos].to_int()
}

///|

///|

///|
fn Reader::read_label(self : Reader) -> String raise ComponentParseError {
  let len = self.read_leb_u32()
  let bytes = self.read_bytes(len)
  decode_utf8_validated(bytes)
}

///|
fn parse_prim_valtype(op : Int) -> PrimValType? {
  match op {
    0x7f => Some(Bool)
    0x7e => Some(S8)
    0x7d => Some(U8)
    0x7c => Some(S16)
    0x7b => Some(U16)
    0x7a => Some(S32)
    0x79 => Some(U32)
    0x78 => Some(S64)
    0x77 => Some(U64)
    0x76 => Some(F32)
    0x75 => Some(F64)
    0x74 => Some(Char)
    0x73 => Some(String)
    0x64 => Some(ErrorContext)
    _ => None
  }
}

///|
fn parse_valtype(reader : Reader) -> ValType raise ComponentParseError {
  let b = reader.peek_u8()
  // Opcodes are negative signed-LEB encodings; indices are nonnegative.
  if b >= 0x40 && (b & 0x80) == 0 {
    let op = reader.read_u8()
    match parse_prim_valtype(op) {
      Some(p) => Prim(p)
      None => raise InvalidTypeSection
    }
  } else {
    TypeIdx(reader.read_typeidx())
  }
}

///|
fn parse_paramlist(reader : Reader) -> Array[Param] raise ComponentParseError {
  let n = reader.read_leb_u32()
  let params = loop ([], 0) {
    (acc, i) =>
      if i >= n {
        acc
      } else {
        let label = reader.read_label()
        let ty = parse_valtype(reader)
        acc.push({ label, ty })
        continue (acc, i + 1)
      }
  }
  params
}

///|
fn parse_resultlist(reader : Reader) -> ValType? raise ComponentParseError {
  let tag = reader.read_u8()
  if tag == 0x00 {
    Some(parse_valtype(reader))
  } else if tag == 0x01 {
    let must_be_zero = reader.read_u8()
    if must_be_zero != 0x00 {
      raise InvalidTypeSection
    }
    None
  } else {
    raise InvalidTypeSection
  }
}

///|
fn parse_functype(
  reader : Reader,
  op : Int,
) -> FuncType raise ComponentParseError {
  let is_async = op == 0x43
  let params = parse_paramlist(reader)
  let result = parse_resultlist(reader)
  { is_async, params, result }
}

///|
fn parse_typedef(reader : Reader) -> TypeDef raise ComponentParseError {
  let op = reader.read_u8()
  match op {
    0x40 | 0x43 => FuncType(parse_functype(reader, op))
    0x41 => {
      // componenttype ::= 0x41 cd*:vec(<componentdecl>)
      let n = reader.read_leb_u32()
      if n != 0 {
        raise UnsupportedTypeOpcode(op)
      }
      ComponentTypeEmpty
    }
    0x42 => {
      // instancetype ::= 0x42 id*:vec(<instancedecl>)
      let n = reader.read_leb_u32()
      if n != 0 {
        raise UnsupportedTypeOpcode(op)
      }
      InstanceTypeEmpty
    }
    _ =>
      match parse_prim_valtype(op) {
        Some(p) => DefValType(p)
        None => raise UnsupportedTypeOpcode(op)
      }
  }
}

///|
pub fn parse_type_section(
  payload : Bytes,
) -> Array[TypeDef] raise ComponentParseError {
  let reader = Reader::new(payload)
  let n = reader.read_leb_u32()
  let types = loop ([], 0) {
    (acc, i) =>
      if i >= n {
        acc
      } else {
        acc.push(parse_typedef(reader))
        continue (acc, i + 1)
      }
  }
  if !reader.is_eof() {
    raise InvalidTypeSection
  }
  types
}
