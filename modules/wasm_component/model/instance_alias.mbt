///|
/// Parsing for component instance and alias sections (sections 5 and 6).

///|
#derive(Debug, Eq)
pub(all) struct InstantiateArg {
  name : String
  sortidx : SortIdx
}

///|
#derive(Debug, Eq)
pub(all) struct InlineExport {
  name : String
  attributes : Array[NameAttribute]
  sortidx : SortIdx
}

///|
#derive(Debug, Eq)
pub(all) enum InstanceExpr {
  Instantiate(Int32, Array[InstantiateArg])
  InlineExports(Array[InlineExport])
}

///|
pub impl Show for InstanceExpr with fn output(self, logger) {
  logger.write_string(@types.compact_show_repr(Repr(self).to_string()))
}

///|
#derive(Debug, Eq)
pub(all) struct Instance {
  expr : InstanceExpr
}

///|
fn parse_inlineexport(
  reader : Reader,
) -> InlineExport raise ComponentParseError {
  let (name, attributes) = parse_annotated_name(
    reader,
    Reader::read_name,
    InvalidInstanceSection,
  )
  let sortidx = parse_sortidx(reader)
  { name, attributes, sortidx, }
}

///|
fn parse_instantiatearg(
  reader : Reader,
) -> InstantiateArg raise ComponentParseError {
  let name = reader.read_name()
  let sortidx = parse_sortidx(reader)
  { name, sortidx, }
}

///|
fn parse_instanceexpr(
  reader : Reader,
) -> InstanceExpr raise ComponentParseError {
  match reader.read_u8() {
    0 =>
      Instantiate(
        reader.read_leb_u32(),
        reader.read_vector(parse_instantiatearg),
      )
    1 => InlineExports(reader.read_vector(parse_inlineexport))
    _ => raise InvalidInstanceSection
  }
}

///|
pub fn parse_instance_section(
  payload : Bytes,
) -> Array[Instance] raise ComponentParseError {
  parse_vector_section(
    payload,
    reader => { expr: parse_instanceexpr(reader), },
    InvalidInstanceSection,
  )
}

///|
#derive(Debug, Eq)
pub(all) enum AliasTarget {
  Export(Int32, String)
  CoreExport(Int32, String)
  Outer(Int32, Int32)
}

///|
#derive(Debug, Eq)
pub(all) struct Alias {
  sort : Sort
  target : AliasTarget
}

///|
pub impl Show for Alias with fn output(self, logger) {
  logger.write_string(@types.compact_show_repr(Repr(self).to_string()))
}

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
  { sort, target, }
}

///|
pub fn parse_alias_section(
  payload : Bytes,
) -> Array[Alias] raise ComponentParseError {
  parse_vector_section(payload, parse_alias, InvalidAliasSection)
}
