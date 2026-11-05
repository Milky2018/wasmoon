///|
/// Parsing for core instance section (section 2 in the component binary format).

///|
#derive(Debug, Eq)
pub(all) struct CoreInstantiateArg {
  name : String
  sortidx : SortIdx
}

///|
#derive(Debug, Eq)
pub(all) struct CoreInlineExport {
  name : String
  sortidx : SortIdx
}

///|
#derive(Debug, Eq)
pub(all) enum CoreInstanceExpr {
  Instantiate(Int32, Array[CoreInstantiateArg])
  InlineExports(Array[CoreInlineExport])
}

///|
#derive(Debug, Eq)
pub(all) struct CoreInstanceDecl {
  expr : CoreInstanceExpr
}

///|
fn parse_core_named_index(
  reader : Reader,
) -> (String, SortIdx) raise ComponentParseError {
  let name = reader.read_name()
  let kind = reader.read_u8()
  let idx = reader.read_leb_u32()
  (name, { sort: Core(kind), idx, })
}

///|
fn parse_core_instanceexpr(
  reader : Reader,
) -> CoreInstanceExpr raise ComponentParseError {
  match reader.read_u8() {
    0 => {
      let module_idx = reader.read_leb_u32()
      let args = reader.read_vector(r => {
        let (name, sortidx) = parse_core_named_index(r)
        ({ name, sortidx, } : CoreInstantiateArg)
      })
      Instantiate(module_idx, args)
    }
    1 =>
      InlineExports(
        reader.read_vector(r => {
          let (name, sortidx) = parse_core_named_index(r)
          { name, sortidx, }
        }),
      )
    _ => raise InvalidInstanceSection
  }
}

///|
pub fn parse_core_instance_section(
  payload : Bytes,
) -> Array[CoreInstanceDecl] raise ComponentParseError {
  parse_vector_section(
    payload,
    reader => { expr: parse_core_instanceexpr(reader), },
    InvalidInstanceSection,
  )
}
