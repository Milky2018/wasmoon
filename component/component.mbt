///|
/// High-level parsed representation of a component.
///
/// This is intentionally partial: for now we only parse a subset of sections
/// (types/imports/exports) while keeping the raw binary sections available for
/// later instantiation work.

///|
pub(all) struct Component {
  binary : ComponentBinary
  types : Array[TypeDef]
  imports : Array[Import]
  exports : Array[Export]
} derive(Show, Eq)

///|
pub fn parse_component(bytes : Bytes) -> Component raise ComponentParseError {
  let binary = parse_component_binary(bytes)
  let types : Array[TypeDef] = []
  let imports : Array[Import] = []
  let exports : Array[Export] = []
  for s in binary.sections {
    if s.id == 7 {
      for t in parse_type_section(s.payload) {
        types.push(t)
      }
    } else if s.id == 10 {
      for i in parse_import_section(s.payload) {
        imports.push(i)
      }
    } else if s.id == 11 {
      for e in parse_export_section(s.payload) {
        exports.push(e)
      }
    } else {
      ()
    }
  }
  { binary, types, imports, exports }
}
