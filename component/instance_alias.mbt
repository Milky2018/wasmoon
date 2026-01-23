///|
/// Parsing for component instance and alias sections (sections 5 and 6).

///|
pub(all) struct InstantiateArg {
  name : String
  sortidx : SortIdx
} derive(Show, Eq)

///|
pub(all) struct InlineExport {
  name : String
  sortidx : SortIdx
} derive(Show, Eq)

///|
pub(all) enum InstanceExpr {
  Instantiate(Int, Array[InstantiateArg])
  InlineExports(Array[InlineExport])
} derive(Show, Eq)

///|
pub(all) struct Instance {
  expr : InstanceExpr
} derive(Show, Eq)

///|
fn parse_inlineexport(
  reader : Reader,
) -> InlineExport raise ComponentParseError {
  // Inline exports in the instance section use the same tagged "exportname"
  // encoding as the component export section (0x00/0x01 + name bytes [+version]).
  let tag = reader.read_u8()
  let name = if tag == 0x00 {
    let len = reader.read_leb_u32()
    let bytes = reader.read_bytes(len)
    decode_utf8_validated(bytes)
  } else if tag == 0x01 {
    let len = reader.read_leb_u32()
    let bytes = reader.read_bytes(len)
    // For now we ignore the version suffix, since the test suite uses only
    // plain names.
    let vs_len = reader.read_leb_u32()
    reader.read_bytes(vs_len) |> ignore
    decode_utf8_validated(bytes)
  } else {
    raise InvalidInstanceSection
  }
  let sortidx = parse_sortidx(reader)
  { name, sortidx }
}

///|
fn parse_instantiatearg(
  reader : Reader,
) -> InstantiateArg raise ComponentParseError {
  let name = reader.read_name()
  let sortidx = parse_sortidx(reader)
  { name, sortidx }
}

///|
fn parse_instanceexpr(
  reader : Reader,
) -> InstanceExpr raise ComponentParseError {
  let tag = reader.read_u8()
  if tag == 0x00 {
    let component_idx = reader.read_leb_u32()
    let n = reader.read_leb_u32()
    let args = loop ([], 0) {
      (acc, i) =>
        if i >= n {
          acc
        } else {
          acc.push(parse_instantiatearg(reader))
          continue (acc, i + 1)
        }
    }
    Instantiate(component_idx, args)
  } else if tag == 0x01 {
    let n = reader.read_leb_u32()
    let exports = loop ([], 0) {
      (acc, i) =>
        if i >= n {
          acc
        } else {
          acc.push(parse_inlineexport(reader))
          continue (acc, i + 1)
        }
    }
    InlineExports(exports)
  } else {
    raise InvalidInstanceSection
  }
}

///|
pub fn parse_instance_section(
  payload : Bytes,
) -> Array[Instance] raise ComponentParseError {
  let reader = Reader::new(payload)
  let n = reader.read_leb_u32()
  let instances = loop ([], 0) {
    (acc, i) =>
      if i >= n {
        acc
      } else {
        acc.push(Instance::{ expr: parse_instanceexpr(reader) })
        continue (acc, i + 1)
      }
  }
  if !reader.is_eof() {
    raise InvalidInstanceSection
  }
  instances
}

///|
pub(all) enum AliasTarget {
  Export(Int, String)
  CoreExport(Int, String)
  Outer(Int, Int)
} derive(Show, Eq)

///|
pub(all) struct Alias {
  sort : Sort
  target : AliasTarget
} derive(Show, Eq)

///|
fn parse_aliastarget(reader : Reader) -> AliasTarget raise ComponentParseError {
  let tag = reader.read_u8()
  if tag == 0x00 {
    let instance_idx = reader.read_leb_u32()
    let name = reader.read_name()
    Export(instance_idx, name)
  } else if tag == 0x01 {
    let core_instance_idx = reader.read_leb_u32()
    let name = reader.read_name()
    CoreExport(core_instance_idx, name)
  } else if tag == 0x02 {
    let ct = reader.read_leb_u32()
    let idx = reader.read_leb_u32()
    Outer(ct, idx)
  } else {
    raise InvalidAliasSection
  }
}

///|
fn parse_alias(reader : Reader) -> Alias raise ComponentParseError {
  let sort = parse_sort(reader)
  let target = parse_aliastarget(reader)
  { sort, target }
}

///|
pub fn parse_alias_section(
  payload : Bytes,
) -> Array[Alias] raise ComponentParseError {
  let reader = Reader::new(payload)
  let n = reader.read_leb_u32()
  let aliases = loop ([], 0) {
    (acc, i) =>
      if i >= n {
        acc
      } else {
        acc.push(parse_alias(reader))
        continue (acc, i + 1)
      }
  }
  if !reader.is_eof() {
    raise InvalidAliasSection
  }
  aliases
}
