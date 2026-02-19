///|
/// Parsing for component import/export sections (sections 10 and 11).
///
/// This is still a subset: we primarily parse the framing and enough structure
/// to keep index spaces and types wired up for later validation/linking.

///|
pub(all) enum Sort {
  Core(Int) // core:sort opcode (0x00..)
  Func
  Value
  Type
  Component
  Instance
} derive(Show, Eq)

///|
pub(all) struct SortIdx {
  sort : Sort
  idx : Int
} derive(Show, Eq)

///|
pub(all) enum TypeBound {
  Eq(Int)
  SubResource
} derive(Show, Eq)

///|
pub(all) enum ValueBound {
  Eq(Int)
  Type(ValType)
} derive(Show, Eq)

///|
pub(all) enum ExternDesc {
  CoreModuleType(Int) // core:typeidx (u32)
  FuncType(Int) // typeidx
  Value(ValueBound)
  Type(TypeBound)
  ComponentType(Int) // typeidx
  InstanceType(Int) // typeidx
} derive(Show, Eq)

///|
pub(all) enum ImportName {
  Plain(Bytes)
  WithVersion(Bytes, Bytes)
} derive(Show, Eq)

///|
pub(all) enum ExportName {
  Plain(Bytes)
  WithVersion(Bytes, Bytes)
} derive(Show, Eq)

///|
pub(all) struct Import {
  name : ImportName
  desc : ExternDesc
} derive(Show, Eq)

///|
pub(all) struct Export {
  name : ExportName
  sortidx : SortIdx
  desc : ExternDesc?
} derive(Show, Eq)

///|
fn parse_name_annot(reader : Reader) -> Bytes raise ComponentParseError {
  let len = reader.read_leb_u32()
  reader.read_bytes(len)
}

///|
fn parse_versionsuffix(reader : Reader) -> Bytes raise ComponentParseError {
  let len = reader.read_leb_u32()
  reader.read_bytes(len)
}

///|
fn parse_importname(reader : Reader) -> ImportName raise ComponentParseError {
  let tag = reader.read_u8()
  if tag == 0x00 {
    Plain(parse_name_annot(reader))
  } else if tag == 0x01 {
    let name = parse_name_annot(reader)
    let vs = parse_versionsuffix(reader)
    WithVersion(name, vs)
  } else {
    raise InvalidTypeSection
  }
}

///|
fn parse_exportname(reader : Reader) -> ExportName raise ComponentParseError {
  let tag = reader.read_u8()
  if tag == 0x00 {
    Plain(parse_name_annot(reader))
  } else if tag == 0x01 {
    let name = parse_name_annot(reader)
    let vs = parse_versionsuffix(reader)
    WithVersion(name, vs)
  } else {
    raise InvalidTypeSection
  }
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
  { sort, idx }
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
fn parse_opt_externdesc(
  reader : Reader,
) -> ExternDesc? raise ComponentParseError {
  let tag = reader.read_u8()
  if tag == 0x00 {
    None
  } else if tag == 0x01 {
    Some(parse_externdesc(reader))
  } else {
    raise InvalidTypeSection
  }
}

///|
pub fn parse_import_section(
  payload : Bytes,
) -> Array[Import] raise ComponentParseError {
  let reader = Reader::new(payload)
  let n = reader.read_leb_u32()
  let imports : Array[Import] = []
  for _i in 0..<n {
    let start_pos = reader.pos
    // New encoding: tagged import names (0x00 plain, 0x01 with-version).
    // Backwards compat: wasm-tools accepts an older encoding where 0x01 was
    // used as a "plain name" tag with no version suffix.
    let (name, desc) = try {
      let name = parse_importname(reader)
      let desc = parse_externdesc(reader)
      (name, desc)
    } catch {
      e => {
        reader.pos = start_pos
        let tag = reader.read_u8()
        if tag == 0x01 {
          let name = ImportName::Plain(parse_name_annot(reader))
          let desc = parse_externdesc(reader)
          (name, desc)
        } else {
          raise e
        }
      }
    }
    imports.push({ name, desc })
  }
  if !reader.is_eof() {
    raise InvalidTypeSection
  }
  imports
}

///|
pub fn parse_export_section(
  payload : Bytes,
) -> Array[Export] raise ComponentParseError {
  let reader = Reader::new(payload)
  let n = reader.read_leb_u32()
  let exports = loop ([], 0) {
    (acc, i) =>
      if i >= n {
        acc
      } else {
        let name = parse_exportname(reader)
        let sortidx = parse_sortidx(reader)
        let desc = parse_opt_externdesc(reader)
        acc.push({ name, sortidx, desc })
        continue (acc, i + 1)
      }
  }
  if !reader.is_eof() {
    raise InvalidTypeSection
  }
  exports
}
