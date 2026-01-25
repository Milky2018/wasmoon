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
/// A subset of instance type declarations (enough for wasmtime/component-spec).
pub(all) enum InstanceDecl {
  // Embedded core typedef (module type / func type / etc).
  CoreType(Bytes)
  Type(TypeDef)
  // (alias outer ...) inside an instance type declaration.
  // `kind` is the component model external kind discriminator (e.g. Type=0x03).
  AliasOuter(Int, Int, Int)
  // (alias export ...) inside an instance type declaration.
  // `kind` is the component model external kind discriminator.
  AliasInstanceExport(Int, Int, String)
  Export(String, ExternDesc)
} derive(Show, Eq)

///|
/// A subset of component type declarations (enough for WIT-encoded components).
pub(all) enum ComponentDecl {
  // Embedded core typedef (module type / func type / etc).
  CoreType(Bytes)
  Type(TypeDef)
  // (alias outer ...) inside a component type declaration.
  AliasOuter(Int, Int, Int)
  // (alias export ...) inside a component type declaration.
  AliasInstanceExport(Int, Int, String)
  Import(String, ExternDesc)
  Export(String, ExternDesc)
} derive(Show, Eq)

///|
pub(all) enum TypeDef {
  DefValType(PrimValType)
  FuncType(FuncType)
  // Nominal resource type. `id` is filled at instantiation time.
  // `rep` is the core wasm value type (e.g. i32=0x7f).
  // `dtor` is an optional destructor core func index.
  ResourceType(Int, Int, Int?)
  ComponentType(Array[ComponentDecl])
  InstanceTypeEmpty
  InstanceType(Array[InstanceDecl])
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
fn parse_exportname_string(reader : Reader) -> String raise ComponentParseError {
  let tag = reader.read_u8()
  if tag == 0x00 {
    let len = reader.read_leb_u32()
    let bytes = reader.read_bytes(len)
    decode_utf8_validated(bytes)
  } else if tag == 0x01 {
    let len = reader.read_leb_u32()
    let bytes = reader.read_bytes(len)
    let vs_len = reader.read_leb_u32()
    reader.read_bytes(vs_len) |> ignore
    decode_utf8_validated(bytes)
  } else {
    raise InvalidTypeSection
  }
}

///|
fn parse_typebound_for_instancedecl(
  reader : Reader,
) -> TypeBound raise ComponentParseError {
  let tag = reader.read_u8()
  if tag == 0x00 {
    TypeBound::Eq(reader.read_typeidx())
  } else if tag == 0x01 {
    TypeBound::SubResource
  } else {
    raise InvalidTypeSection
  }
}

///|
fn parse_valuebound_for_instancedecl(
  reader : Reader,
) -> ValueBound raise ComponentParseError {
  let tag = reader.read_u8()
  if tag == 0x00 {
    ValueBound::Eq(reader.read_leb_u32())
  } else if tag == 0x01 {
    ValueBound::Type(parse_valtype(reader))
  } else {
    raise InvalidTypeSection
  }
}

///|
fn parse_externdesc_for_instancedecl(
  reader : Reader,
) -> ExternDesc raise ComponentParseError {
  let tag = reader.read_u8()
  if tag == 0x00 {
    let must_be_core_module = reader.read_u8()
    if must_be_core_module != 0x11 {
      raise InvalidTypeSection
    }
    ExternDesc::CoreModuleType(reader.read_leb_u32())
  } else if tag == 0x01 {
    ExternDesc::FuncType(reader.read_typeidx())
  } else if tag == 0x02 {
    ExternDesc::Value(parse_valuebound_for_instancedecl(reader))
  } else if tag == 0x03 {
    ExternDesc::Type(parse_typebound_for_instancedecl(reader))
  } else if tag == 0x04 {
    ExternDesc::ComponentType(reader.read_typeidx())
  } else if tag == 0x05 {
    ExternDesc::InstanceType(reader.read_typeidx())
  } else {
    raise InvalidTypeSection
  }
}

///|
fn parse_alias_kind(reader : Reader) -> Int raise ComponentParseError {
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
  let nparams = reader.read_leb_u32()
  for _i in 0..<nparams {
    reader.read_u8() |> ignore
  }
  let nresults = reader.read_leb_u32()
  for _i in 0..<nresults {
    reader.read_u8() |> ignore
  }
}

///|
fn skip_core_extern_type(
  reader : Reader,
  kind : Int,
) -> Unit raise ComponentParseError {
  match kind {
    0x00 => reader.read_leb_u32() |> ignore // func type index
    0x01 => {
      reader.read_u8() |> ignore // elem/ref type
      skip_limits(reader)
    }
    0x02 => skip_limits(reader)
    0x03 => {
      reader.read_u8() |> ignore // valtype
      reader.read_u8() |> ignore // mut
    }
    0x04 => reader.read_leb_u32() |> ignore // tag type index
    _ => raise InvalidTypeSection
  }
}

///|
fn skip_core_moduletype(reader : Reader) -> Unit raise ComponentParseError {
  let ndecls = reader.read_leb_u32()
  for _i in 0..<ndecls {
    let tag = reader.read_u8()
    match tag {
      0x00 => {
        reader.read_label() |> ignore // module
        reader.read_label() |> ignore // name
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
        reader.read_label() |> ignore // name
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
  } else {
    raise InvalidTypeSection
  }
}

///|
fn parse_instancedecl(
  reader : Reader,
) -> InstanceDecl raise ComponentParseError {
  let tag = reader.read_u8()
  if tag == 0x00 {
    let start = reader.pos
    skip_core_typedef(reader)
    let end = reader.pos
    InstanceDecl::CoreType(bytes_sub(reader.data, start, end))
  } else if tag == 0x01 {
    InstanceDecl::Type(parse_typedef(reader))
  } else if tag == 0x02 {
    // aliasdecl ::= 0x02 kind:<externkind> target:<aliastarget> ...
    let kind = parse_alias_kind(reader)
    let target = reader.read_u8()
    if target == 0x00 {
      // InstanceExport { instance_index, name }
      let instance_idx = reader.read_leb_u32()
      // Alias targets use the plain `name` string encoding (length + bytes),
      // not the export-name string encoding used by import/export decls.
      let name = reader.read_label()
      InstanceDecl::AliasInstanceExport(kind, instance_idx, name)
    } else if target == 0x02 {
      // Outer { count, index }
      let count = reader.read_leb_u32()
      let idx = reader.read_leb_u32()
      InstanceDecl::AliasOuter(kind, count, idx)
    } else {
      raise InvalidTypeSection
    }
  } else if tag == 0x04 {
    let name = parse_exportname_string(reader)
    let desc = parse_externdesc_for_instancedecl(reader)
    InstanceDecl::Export(name, desc)
  } else {
    raise UnsupportedTypeOpcode(tag)
  }
}

///|
fn parse_componentdecl(
  reader : Reader,
) -> ComponentDecl raise ComponentParseError {
  let tag = reader.read_u8()
  if tag == 0x00 {
    let start = reader.pos
    skip_core_typedef(reader)
    let end = reader.pos
    ComponentDecl::CoreType(bytes_sub(reader.data, start, end))
  } else if tag == 0x01 {
    ComponentDecl::Type(parse_typedef(reader))
  } else if tag == 0x02 {
    // aliasdecl ::= 0x02 kind:<externkind> target:<aliastarget> ...
    let kind = parse_alias_kind(reader)
    let target = reader.read_u8()
    if target == 0x00 {
      // InstanceExport { instance_index, name }
      let instance_idx = reader.read_leb_u32()
      let name = reader.read_label()
      ComponentDecl::AliasInstanceExport(kind, instance_idx, name)
    } else if target == 0x02 {
      // Outer { count, index }
      let count = reader.read_leb_u32()
      let idx = reader.read_leb_u32()
      ComponentDecl::AliasOuter(kind, count, idx)
    } else {
      raise InvalidTypeSection
    }
  } else if tag == 0x03 {
    let name = parse_exportname_string(reader)
    let desc = parse_externdesc_for_instancedecl(reader)
    ComponentDecl::Import(name, desc)
  } else if tag == 0x04 {
    let name = parse_exportname_string(reader)
    let desc = parse_externdesc_for_instancedecl(reader)
    ComponentDecl::Export(name, desc)
  } else {
    raise UnsupportedTypeOpcode(tag)
  }
}

///|
fn parse_typedef(reader : Reader) -> TypeDef raise ComponentParseError {
  let op = reader.read_u8()
  match op {
    0x40 | 0x43 => FuncType(parse_functype(reader, op))
    0x3f => {
      // resourcetype ::= 0x3f rep:<corevaltype> dtor:<opt u32>
      let rep = reader.read_u8()
      let has_dtor = reader.read_u8()
      let dtor = if has_dtor == 0x00 {
        None
      } else if has_dtor == 0x01 {
        Some(reader.read_leb_u32())
      } else {
        raise InvalidTypeSection
      }
      ResourceType(-1, rep, dtor)
    }
    0x41 => {
      // componenttype ::= 0x41 cd*:vec(<componentdecl>)
      let n = reader.read_leb_u32()
      let decls = loop ([], 0) {
        (acc, i) =>
          if i >= n {
            acc
          } else {
            acc.push(parse_componentdecl(reader))
            continue (acc, i + 1)
          }
      }
      ComponentType(decls)
    }
    0x42 => {
      // instancetype ::= 0x42 id*:vec(<instancedecl>)
      let n = reader.read_leb_u32()
      if n == 0 {
        InstanceTypeEmpty
      } else {
        let decls = loop ([], 0) {
          (acc, i) =>
            if i >= n {
              acc
            } else {
              acc.push(parse_instancedecl(reader))
              continue (acc, i + 1)
            }
        }
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
