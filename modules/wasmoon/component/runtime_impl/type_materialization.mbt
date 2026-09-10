///|
/// Binary type indices stay fixed while imported dependencies use trailing slots.
fn BuildState::append_declared_type(
  self : BuildState,
  value : TypeDef?,
) -> Unit {
  let index = self.next_declared_type.val
  if index == self.types.length() {
    self.types.push(value)
  } else {
    self.types[index] = value
  }
  self.next_declared_type.val += 1
}

///|
fn clone_materialized_optional_type(
  value : TypeDef?,
  source : Array[TypeDef?],
  destination : Array[TypeDef?],
) -> TypeDef? raise ComponentRuntimeError {
  match value {
    None => None
    Some(value) =>
      Some(clone_materialized_type_def(value, source, destination, Map([])))
  }
}

///|
fn count_component_type_slots(
  component : Component,
) -> Int raise ComponentRuntimeError {
  let mut count = 0
  for section in component.binary.sections {
    try {
      match section.id {
        7 => count += Reader::Reader(section.payload).read_leb_u32()
        6 =>
          for alias_decl in parse_alias_section(section.payload) {
            if alias_decl.sort is Type {
              count += 1
            }
          }
        10 =>
          for import_ in parse_import_section(section.payload) {
            if import_.desc is Type(_) {
              count += 1
            }
          }
        11 =>
          for export_ in parse_export_section(section.payload) {
            if export_.sortidx.sort is Type {
              count += 1
            }
          }
        _ => ()
      }
    } catch {
      error => raise ComponentParseError(error.to_string())
    }
  }
  count
}
