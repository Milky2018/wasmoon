///|
/// Parsing for component type section (section 7 in the component binary format).
///
/// For now, this only supports a small subset (primvaltype + basic functype)
/// to unblock end-to-end parsing and testing.

///|
#derive(Debug, Eq)
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
}

///|
#derive(Debug, Eq)
pub(all) enum ValType {
  TypeIdx(Int32)
  Prim(PrimValType)
}

///|
#derive(Debug, Eq)
pub(all) enum ResourceKind {
  /// Resources defined within a component.
  GuestDefined
  /// Resources imported from the host environment.
  HostDefined
}

///|
#derive(Debug, Eq)
pub(all) struct Param {
  label : String
  ty : ValType
}

///|
#derive(Debug, Eq)
pub(all) struct FuncType {
  is_async : Bool
  params : Array[Param]
  result : ValType?
}

///|
/// A subset of instance type declarations (enough for wasmtime/component-spec).
#derive(Debug, Eq)
pub(all) enum InstanceDecl {
  // Embedded core typedef (module type / func type / etc).
  CoreType(Bytes)
  Type(TypeDef)
  // (alias outer ...) inside an instance type declaration.
  // `kind` is the component model external kind discriminator (e.g. Type=0x03).
  AliasOuter(Int32, Int32, Int32)
  // (alias export ...) inside an instance type declaration.
  // `kind` is the component model external kind discriminator.
  AliasInstanceExport(Int32, Int32, String)
  Export(String, Array[NameAttribute], ExternDesc)
}

///|
/// A subset of component type declarations (enough for WIT-encoded components).
#derive(Debug, Eq)
pub(all) enum ComponentDecl {
  // Embedded core typedef (module type / func type / etc).
  CoreType(Bytes)
  Type(TypeDef)
  // (alias outer ...) inside a component type declaration.
  AliasOuter(Int32, Int32, Int32)
  // (alias export ...) inside a component type declaration.
  AliasInstanceExport(Int32, Int32, String)
  Import(String, Array[NameAttribute], ExternDesc)
  Export(String, Array[NameAttribute], ExternDesc)
}

///|
#derive(Debug, Eq)
pub(all) enum TypeDef {
  DefValType(PrimValType)
  FuncType(FuncType)
  List(ValType)
  FixedList(ValType, Int32)
  MapType(ValType, ValType)
  Record(Array[RecordField])
  Variant(Array[VariantCase])
  Tuple(Array[ValType])
  Flags(Array[String])
  Enum(Array[String])
  Option(ValType)
  Result(ValType?, ValType?)
  Own(Int32)
  Borrow(Int32)
  Stream(ValType?)
  Future(ValType?)
  // Nominal resource type. `id` is filled at instantiation time.
  // `rep` is the core wasm value type (e.g. i32=0x7f).
  // `dtor` is an optional destructor core func index.
  // `kind` tracks whether the resource originates from the component or host.
  ResourceType(Int32, Int32, Int32?, ResourceKind)
  ComponentType(Array[ComponentDecl])
  InstanceTypeEmpty
  InstanceType(Array[InstanceDecl])
}

///|
pub impl Show for TypeDef with fn output(self, logger) {
  logger.write_string(@types.compact_show_repr(Repr(self).to_string()))
}

///|
#derive(Debug, Eq)
pub(all) struct RecordField {
  label : String
  ty : ValType
}

///|
#derive(Debug, Eq)
pub(all) struct VariantCase {
  label : String
  ty : ValType?
  // `refines` points at a previously defined case index.
  refines : Int32?
}

///|

///|
fn parse_prim_valtype(op : Int32) -> PrimValType? {
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
fn parse_valtype(
  reader : Reader,
  invalid~ : ComponentParseError = InvalidTypeSection,
) -> ValType raise ComponentParseError {
  let value = reader.read_s33()
  if 0L <= value && value <= 0x7FFF_FFFFL {
    return TypeIdx(value.to_int())
  }
  if -64L <= value &&
    value < 0L &&
    parse_prim_valtype(value.to_int() & 0x7F) is Some(primitive) {
    return Prim(primitive)
  }
  raise invalid
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
  op : Int32,
) -> FuncType raise ComponentParseError {
  let is_async = op == 0x43
  let params : Array[Param] = reader.read_vector(r => {
    label: r.read_name(),
    ty: parse_valtype(r),
  })
  let result = parse_resultlist(reader)
  { is_async, params, result, }
}

///|
fn parse_alias_kind(reader : Reader) -> Int32 raise ComponentParseError {
  // Alias kinds use the same encoding as Sort in the import/export sections:
  // 0x00 <core_sort> for core items, or a single-byte tag for component items.
  let tag = reader.read_u8()
  if tag == 0x00 {
    let core_sort = reader.read_u8()
    // Encode core sorts in a separate range to avoid collisions with 0x01..0x05.
    0x100 + core_sort
  } else {
    tag
  }
}

///|
fn skip_limits(reader : Reader) -> Unit raise ComponentParseError {
  let flags = reader.read_u8()
  reader.read_leb_u32() |> ignore
  if (flags & 0x01) != 0 {
    reader.read_leb_u32() |> ignore
  }
}

///|
fn skip_core_functype_inline(reader : Reader) -> Unit raise ComponentParseError {
  let form = reader.read_u8()
  if form != 0x60 {
    raise InvalidTypeSection
  }
  skip_core_functype_body(reader)
}

///|
fn skip_core_functype_body(reader : Reader) -> Unit raise ComponentParseError {
  let nparams = reader.read_count()
  for _i in 0..<nparams {
    skip_core_valtype(reader)
  }
  let nresults = reader.read_count()
  for _i in 0..<nresults {
    skip_core_valtype(reader)
  }
}

///|
fn skip_core_valtype(reader : Reader) -> Unit raise ComponentParseError {
  let opcode = reader.read_u8()
  if opcode == 0x63 || opcode == 0x64 {
    reader.read_s33() |> ignore
  }
}

///|
fn skip_core_extern_type(
  reader : Reader,
  kind : Int32,
) -> Unit raise ComponentParseError {
  match kind {
    0x00 => reader.read_leb_u32() |> ignore // func type index
    0x01 => {
      skip_core_valtype(reader)
      skip_limits(reader)
    }
    0x02 => skip_limits(reader)
    0x03 => {
      skip_core_valtype(reader)
      reader.read_u8() |> ignore // mut
    }
    0x04 => {
      if reader.read_u8() != 0x00 {
        raise InvalidTypeSection
      }
      reader.read_leb_u32() |> ignore // tag type index
    }
    _ => raise InvalidTypeSection
  }
}

///|
fn skip_core_moduletype(reader : Reader) -> Unit raise ComponentParseError {
  let ndecls = reader.read_count()
  for _i in 0..<ndecls {
    let tag = reader.read_u8()
    match tag {
      0x00 => {
        reader.read_name() |> ignore // module
        reader.read_name() |> ignore // name
        let kind = reader.read_u8()
        skip_core_extern_type(reader, kind)
      }
      0x01 => skip_core_functype_inline(reader)
      0x02 => {
        // alias decl: sort + target + indices
        reader.read_u8() |> ignore
        let target = reader.read_u8()
        if target == 0x01 {
          reader.read_leb_u32() |> ignore
          reader.read_leb_u32() |> ignore
        } else {
          raise InvalidTypeSection
        }
      }
      0x03 => {
        reader.read_name() |> ignore // name
        let kind = reader.read_u8()
        skip_core_extern_type(reader, kind)
      }
      _ => raise InvalidTypeSection
    }
  }
}

///|
fn skip_core_typedef(reader : Reader) -> Unit raise ComponentParseError {
  let op = reader.read_u8()
  if op == 0x50 {
    skip_core_moduletype(reader)
  } else if op == 0x60 {
    skip_core_functype_body(reader)
  } else if op == 0x00 {
    if reader.read_u8() != 0x50 {
      raise InvalidTypeSection
    }
    let supertype_count = reader.read_count()
    for _ in 0..<supertype_count {
      reader.read_leb_u32() |> ignore
    }
    if reader.read_u8() != 0x60 {
      raise InvalidTypeSection
    }
    skip_core_functype_body(reader)
  } else {
    raise InvalidTypeSection
  }
}

///|
fn parse_type_declaration(
  reader : Reader,
  allow_import : Bool,
) -> ComponentDecl raise ComponentParseError {
  match reader.read_u8() {
    0 => {
      let start = reader.pos
      skip_core_typedef(reader)
      CoreType(reader.data[start:reader.pos].to_owned())
    }
    1 => Type(parse_typedef(reader))
    2 => {
      let kind = parse_alias_kind(reader)
      match reader.read_u8() {
        0 =>
          AliasInstanceExport(kind, reader.read_leb_u32(), reader.read_name())
        2 => AliasOuter(kind, reader.read_leb_u32(), reader.read_leb_u32())
        _ => raise InvalidTypeSection
      }
    }
    3 if allow_import => {
      let (name, attrs) = parse_annotated_name(
        reader,
        Reader::read_name,
        InvalidTypeSection,
      )
      Import(name, attrs, parse_externdesc(reader))
    }
    4 => {
      let (name, attrs) = parse_annotated_name(
        reader,
        Reader::read_name,
        InvalidTypeSection,
      )
      Export(name, attrs, parse_externdesc(reader))
    }
    tag => raise UnsupportedTypeOpcode(tag)
  }
}

///|
fn parse_instancedecl(
  reader : Reader,
) -> InstanceDecl raise ComponentParseError {
  match parse_type_declaration(reader, false) {
    CoreType(bytes) => CoreType(bytes)
    Type(ty) => Type(ty)
    AliasOuter(kind, count, idx) => AliasOuter(kind, count, idx)
    AliasInstanceExport(kind, idx, name) => AliasInstanceExport(kind, idx, name)
    Export(name, attrs, desc) => Export(name, attrs, desc)
    Import(_, _, _) => raise UnsupportedTypeOpcode(3)
  }
}

///|
fn parse_typedef(reader : Reader) -> TypeDef raise ComponentParseError {
  let op = reader.read_u8()
  match op {
    0x40 | 0x43 => FuncType(parse_functype(reader, op))
    0x65 => Future(reader.read_optional(r => parse_valtype(r)))
    0x66 => Stream(reader.read_optional(r => parse_valtype(r)))
    0x68 => Borrow(reader.read_typeidx())
    0x69 => Own(reader.read_typeidx())
    0x6a =>
      Result(
        reader.read_optional(r => parse_valtype(r)),
        reader.read_optional(r => parse_valtype(r)),
      )
    0x6b => Option(parse_valtype(reader))
    0x6d => Enum(reader.read_vector(Reader::read_name))
    0x6e => Flags(reader.read_vector(Reader::read_name))
    0x6f => Tuple(reader.read_vector(r => parse_valtype(r)))
    0x70 => List(parse_valtype(reader))
    0x67 => {
      let ty = parse_valtype(reader)
      let len = reader.read_leb_u32()
      FixedList(ty, len)
    }
    0x63 => MapType(parse_valtype(reader), parse_valtype(reader))
    0x71 =>
      Variant(
        reader.read_vector(r => {
          let label = r.read_name()
          let ty = r.read_optional(item => parse_valtype(item))
          let refines = r.read_optional(Reader::read_leb_u32)
          { label, ty, refines, }
        }),
      )
    0x72 =>
      Record(
        reader.read_vector(r => { label: r.read_name(), ty: parse_valtype(r), }),
      )
    0x3f => {
      let rep = reader.read_u8()
      let dtor = reader.read_optional(Reader::read_leb_u32)
      ResourceType(-1, rep, dtor, GuestDefined)
    }
    0x41 =>
      ComponentType(reader.read_vector(r => parse_type_declaration(r, true)))
    0x42 => {
      let decls = reader.read_vector(parse_instancedecl)
      if decls.is_empty() {
        InstanceTypeEmpty
      } else {
        InstanceType(decls)
      }
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
  parse_vector_section(payload, parse_typedef, InvalidTypeSection)
}
