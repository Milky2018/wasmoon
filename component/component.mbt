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
  instances : Array[Instance]
  aliases : Array[Alias]
  canons : Array[Canon]
  start : Start?
  components : Array[Component]
} derive(Show, Eq)

///|
pub fn parse_component(bytes : Bytes) -> Component raise ComponentParseError {
  let binary = parse_component_binary(bytes)
  let types : Array[TypeDef] = []
  let imports : Array[Import] = []
  let exports : Array[Export] = []
  let instances : Array[Instance] = []
  let aliases : Array[Alias] = []
  let canons : Array[Canon] = []
  let mut start : Start? = None
  let components : Array[Component] = []
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
    } else if s.id == 5 {
      for inst in parse_instance_section(s.payload) {
        instances.push(inst)
      }
    } else if s.id == 6 {
      for a in parse_alias_section(s.payload) {
        aliases.push(a)
      }
    } else if s.id == 8 {
      for c in parse_canon_section(s.payload) {
        canons.push(c)
      }
    } else if s.id == 9 {
      start = Some(parse_start_section(s.payload))
    } else if s.id == 4 {
      components.push(parse_component(s.payload))
    } else {
      ()
    }
  }
  {
    binary,
    types,
    imports,
    exports,
    instances,
    aliases,
    canons,
    start,
    components,
  }
}
