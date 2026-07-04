///|
/// Parsing for core instance section (section 2 in the component binary format).

///|
pub(all) struct CoreInstantiateArg {
  name : String
  sortidx : SortIdx
} derive(Debug, Eq)

///|
pub(all) struct CoreInlineExport {
  name : String
  sortidx : SortIdx
} derive(Debug, Eq)

///|
pub(all) enum CoreInstanceExpr {
  Instantiate(Int, Array[CoreInstantiateArg])
  InlineExports(Array[CoreInlineExport])
} derive(Debug, Eq)

///|
pub(all) struct CoreInstanceDecl {
  expr : CoreInstanceExpr
} derive(Debug, Eq)

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
  let sortidx : SortIdx = { sort: Core(kind), idx }
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
  let sortidx : SortIdx = { sort: Core(kind), idx }
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
    let args : Array[CoreInstantiateArg] = []
    for _ in 0..<n {
      args.push(parse_core_instantiatearg(reader))
    }
    Instantiate(module_idx, args)
  } else if tag == 0x01 {
    let n = reader.read_leb_u32()
    let exports : Array[CoreInlineExport] = []
    for _ in 0..<n {
      exports.push(parse_core_inlineexport(reader))
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
  let instances : Array[CoreInstanceDecl] = []
  for _ in 0..<n {
    instances.push({ expr: parse_core_instanceexpr(reader) })
  }
  if !reader.is_eof() {
    raise InvalidInstanceSection
  }
  instances
}
