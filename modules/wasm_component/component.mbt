///|
/// High-level parsed representation of a component.
///
/// This is intentionally partial: for now we only parse a subset of sections
/// (types/imports/exports) while keeping the raw binary sections available for
/// later instantiation work.

///|
pub(all) struct Component {
  binary : ComponentBinary
  core_modules : Array[Bytes]
  core_instances : Array[Bytes]
  core_types : Array[Bytes]
  types : Array[TypeDef]
  imports : Array[Import]
  exports : Array[Export]
  instances : Array[Instance]
  aliases : Array[Alias]
  canons : Array[Canon]
  start : Start?
  components : Array[Component]
} derive(Debug, Eq)

///|
/// Keep `Show` behavior while migrating from deprecated `derive(Show)` to
/// `derive(Debug)`.
pub impl Show for Component with fn output(self, logger) {
  logger.write_string(@types.compact_show_repr(Repr(self).to_string()))
}

///|
pub fn parse_component(bytes : Bytes) -> Component raise ComponentParseError {
  component_from_binary(parse_component_binary(bytes))
}

///|
/// Encode the component's immutable binary snapshot.
///
/// `Bytes` is immutable, so validation evidence can retain and expose this
/// value without granting mutation access to the parsed component graph.
pub fn Component::snapshot_bytes(self : Component) -> Bytes {
  let bytes : Array[Byte] = [b'\x00', b'a', b's', b'm']
  bytes.push((self.binary.version & 0xFF).to_byte())
  bytes.push(((self.binary.version >> 8) & 0xFF).to_byte())
  bytes.push((self.binary.layer & 0xFF).to_byte())
  bytes.push(((self.binary.layer >> 8) & 0xFF).to_byte())
  for section in self.binary.sections {
    bytes.push(section.id.to_byte())
    append_component_leb_u32(bytes, section.payload.length())
    for byte in section.payload {
      bytes.push(byte)
    }
  }
  Bytes::from_array(bytes)
}

///|
fn append_component_leb_u32(bytes : Array[Byte], value : Int) -> Unit {
  for remaining = value {
    let byte = remaining & 0x7F
    let next = remaining >> 7
    if next == 0 {
      bytes.push(byte.to_byte())
      break
    }
    bytes.push((byte | 0x80).to_byte())
    continue next
  }
}

///|
/// Rebuild a component that shares no mutable state with `self`.
pub fn Component::isolated_copy(
  self : Component,
) -> Component raise ComponentParseError {
  parse_component(self.snapshot_bytes())
}

///|
fn component_from_binary(
  binary : ComponentBinary,
) -> Component raise ComponentParseError {
  let core_modules : Array[Bytes] = []
  let core_instances : Array[Bytes] = []
  let core_types : Array[Bytes] = []
  let types : Array[TypeDef] = []
  let imports : Array[Import] = []
  let exports : Array[Export] = []
  let instances : Array[Instance] = []
  let aliases : Array[Alias] = []
  let canons : Array[Canon] = []
  let mut start : Start? = None
  let components : Array[Component] = []
  for s in binary.sections {
    if s.id == 1 {
      core_modules.push(s.payload)
    } else if s.id == 2 {
      core_instances.push(s.payload)
    } else if s.id == 3 {
      core_types.push(s.payload)
    } else if s.id == 7 {
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
    core_modules,
    core_instances,
    core_types,
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
