///|
fn find_component_section_payload(
  comp : @component_types.ComponentBinary,
  id : Int,
) -> Bytes? {
  for s in comp.sections {
    if s.id == id {
      return Some(s.payload)
    }
  }
  None
}
