///|
/// Parsing for component import/export sections (sections 10 and 11).
///
/// This is still a subset: we primarily parse the framing and enough structure
/// to keep index spaces and types wired up for later validation/linking.

///|
#derive(Debug, Eq)
pub(all) enum Sort {
  Core(Int32) // core:sort opcode (0x00..)
  Func
  Value
  Type
  Component
  Instance
}

///|
#derive(Debug, Eq)
pub(all) struct SortIdx {
  sort : Sort
  idx : Int32
}

///|
pub impl Show for SortIdx with fn output(self, logger) {
  logger.write_string(@types.compact_show_repr(Repr(self).to_string()))
}

///|
#derive(Debug, Eq)
pub(all) enum TypeBound {
  Eq(Int32)
  SubResource
}

///|
#derive(Debug, Eq)
pub(all) enum ValueBound {
  Eq(Int32)
  Type(ValType)
}

///|
#derive(Debug, Eq)
pub(all) enum ExternDesc {
  CoreModuleType(Int32) // core:typeidx (u32)
  FuncType(Int32) // typeidx
  Value(ValueBound)
  Type(TypeBound)
  ComponentType(Int32) // typeidx
  InstanceType(Int32) // typeidx
}

///|
pub impl Show for ExternDesc with fn output(self, logger) {
  logger.write_string(@types.compact_show_repr(Repr(self).to_string()))
}

///|
#derive(Debug, Eq)
pub(all) enum ImportName {
  Plain(Bytes)
  WithVersion(Bytes, Bytes)
}

///|
#derive(Debug, Eq)
pub(all) enum ExportName {
  Plain(Bytes)
  WithVersion(Bytes, Bytes)
}

///|
#derive(Debug, Eq)
pub(all) enum NameAttribute {
  Implements(Bytes)
  VersionSuffix(Bytes)
  ExternalId(Bytes)
}

///|
#derive(Debug, Eq)
pub(all) struct Import {
  name : ImportName
  attributes : Array[NameAttribute]
  desc : ExternDesc
}

///|
#derive(Debug, Eq)
pub(all) struct Export {
  name : ExportName
  attributes : Array[NameAttribute]
  sortidx : SortIdx
  desc : ExternDesc?
}

///|
fn parse_attribute(reader : Reader) -> NameAttribute raise ComponentParseError {
  match reader.read_u8() {
    0 => Implements(reader.read_blob())
    1 => VersionSuffix(reader.read_blob())
    2 => ExternalId(reader.read_blob())
    _ => raise InvalidTypeSection
  }
}

///|
fn[A] parse_annotated_name(
  reader : Reader,
  read_name : (Reader) -> A raise ComponentParseError,
  invalid : ComponentParseError,
) -> (A, Array[NameAttribute]) raise ComponentParseError {
  let tag = reader.read_u8()
  if tag > 2 {
    raise invalid
  }
  let name = read_name(reader)
  let attributes = if tag == 2 {
    reader.read_vector(parse_attribute)
  } else {
    []
  }
  (name, attributes)
}

///|
fn parse_sort(reader : Reader) -> Sort raise ComponentParseError {
  let tag = reader.read_u8()
  if tag == 0x00 {
    let core_sort = reader.read_u8()
    Core(core_sort)
  } else if tag == 0x01 {
    Func
  } else if tag == 0x02 {
    Value
  } else if tag == 0x03 {
    Type
  } else if tag == 0x04 {
    Component
  } else if tag == 0x05 {
    Instance
  } else {
    raise InvalidTypeSection
  }
}

///|
fn parse_sortidx(reader : Reader) -> SortIdx raise ComponentParseError {
  let sort = parse_sort(reader)
  let idx = reader.read_leb_u32()
  { sort, idx, }
}

///|
fn parse_typebound(reader : Reader) -> TypeBound raise ComponentParseError {
  let tag = reader.read_u8()
  if tag == 0x00 {
    Eq(reader.read_typeidx())
  } else if tag == 0x01 {
    SubResource
  } else {
    raise InvalidTypeSection
  }
}

///|
fn parse_valuebound(reader : Reader) -> ValueBound raise ComponentParseError {
  let tag = reader.read_u8()
  if tag == 0x00 {
    Eq(reader.read_leb_u32())
  } else if tag == 0x01 {
    Type(parse_valtype(reader))
  } else {
    raise InvalidTypeSection
  }
}

///|
fn parse_externdesc(reader : Reader) -> ExternDesc raise ComponentParseError {
  let tag = reader.read_u8()
  if tag == 0x00 {
    let must_be_core_module = reader.read_u8()
    if must_be_core_module != 0x11 {
      raise InvalidTypeSection
    }
    CoreModuleType(reader.read_leb_u32())
  } else if tag == 0x01 {
    FuncType(reader.read_typeidx())
  } else if tag == 0x02 {
    Value(parse_valuebound(reader))
  } else if tag == 0x03 {
    Type(parse_typebound(reader))
  } else if tag == 0x04 {
    ComponentType(reader.read_typeidx())
  } else if tag == 0x05 {
    InstanceType(reader.read_typeidx())
  } else {
    raise InvalidTypeSection
  }
}

///|
pub fn parse_import_section(
  payload : Bytes,
) -> Array[Import] raise ComponentParseError {
  parse_vector_section(
    payload,
    reader => {
      let (name, attributes) = parse_annotated_name(
        reader,
        Reader::read_blob,
        InvalidTypeSection,
      )
      { name: Plain(name), attributes, desc: parse_externdesc(reader), }
    },
    InvalidTypeSection,
  )
}

///|
pub fn parse_export_section(
  payload : Bytes,
) -> Array[Export] raise ComponentParseError {
  parse_vector_section(
    payload,
    reader => {
      let (name, attributes) = parse_annotated_name(
        reader,
        Reader::read_blob,
        InvalidTypeSection,
      )
      let sortidx = parse_sortidx(reader)
      let desc = reader.read_optional(parse_externdesc)
      { name: Plain(name), attributes, sortidx, desc, }
    },
    InvalidTypeSection,
  )
}
