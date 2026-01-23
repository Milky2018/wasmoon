///|
/// Parsing for core instance section (section 2 in the component binary format).

///|
pub(all) struct CoreInstantiateArg {
  name : String
  sortidx : SortIdx
} derive(Show, Eq)

///|
pub(all) struct CoreInlineExport {
  name : String
  sortidx : SortIdx
} derive(Show, Eq)

///|
pub(all) enum CoreInstanceExpr {
  Instantiate(Int, Array[CoreInstantiateArg])
  InlineExports(Array[CoreInlineExport])
} derive(Show, Eq)

///|
pub(all) struct CoreInstanceDecl {
  expr : CoreInstanceExpr
} derive(Show, Eq)

///|
fn parse_core_inlineexport(
  reader : Reader,
) -> CoreInlineExport raise ComponentParseError {
  let name = reader.read_name()
  // Core instance exports reference the core index spaces directly via a
  // single-byte "kind" followed by an index, unlike the generic SortIdx
  // encoding used in other sections.
  let kind = reader.read_u8()
  let idx = reader.read_leb_u32()
  let sortidx : SortIdx = { sort: Sort::Core(kind), idx }
  { name, sortidx }
}

///|
fn parse_core_instantiatearg(
  reader : Reader,
) -> CoreInstantiateArg raise ComponentParseError {
  let name = reader.read_name()
  // Same encoding as parse_core_inlineexport: (kind:u8, idx:u32).
  let kind = reader.read_u8()
  let idx = reader.read_leb_u32()
  let sortidx : SortIdx = { sort: Sort::Core(kind), idx }
  { name, sortidx }
}

///|
fn parse_core_instanceexpr(
  reader : Reader,
) -> CoreInstanceExpr raise ComponentParseError {
  let tag = reader.read_u8()
  if tag == 0x00 {
    let module_idx = reader.read_leb_u32()
    let n = reader.read_leb_u32()
    let args = loop ([], 0) {
      (acc, i) =>
        if i >= n {
          acc
        } else {
          acc.push(parse_core_instantiatearg(reader))
          continue (acc, i + 1)
        }
    }
    Instantiate(module_idx, args)
  } else if tag == 0x01 {
    let n = reader.read_leb_u32()
    let exports = loop ([], 0) {
      (acc, i) =>
        if i >= n {
          acc
        } else {
          acc.push(parse_core_inlineexport(reader))
          continue (acc, i + 1)
        }
    }
    InlineExports(exports)
  } else {
    raise InvalidInstanceSection
  }
}

///|
pub fn parse_core_instance_section(
  payload : Bytes,
) -> Array[CoreInstanceDecl] raise ComponentParseError {
  let reader = Reader::new(payload)
  let n = reader.read_leb_u32()
  let instances = loop ([], 0) {
    (acc, i) =>
      if i >= n {
        acc
      } else {
        acc.push(CoreInstanceDecl::{ expr: parse_core_instanceexpr(reader) })
        continue (acc, i + 1)
      }
  }
  if !reader.is_eof() {
    raise InvalidInstanceSection
  }
  instances
}
