///|

///|
test "component: parse import/export sections (framing only)" {
  let bytes : Array[Byte] = [
    // magic
    0x00, 0x61, 0x73, 0x6d,
    // version=u16(0x0d), layer=u16(0x01)
     0x0d, 0x00, 0x01, 0x00,
    // section 7 (type), payload size=5
     0x07, 0x05,
    // vec length=1, functype () -> ()
     0x01, 0x40, 0x00, 0x01, 0x00,
    // section 10 (import), payload size=5
     0x0a, 0x05,
    // vec length=1
     0x01,
    // importname' plain, len=0
     0x00, 0x00,
    // externdesc: func typeidx=0
     0x01, 0x00,
    // section 11 (export), payload size=6
     0x0b, 0x06,
    // vec length=1
     0x01,
    // exportname' plain, len=0
     0x00, 0x00,
    // sortidx: func, idx=0
     0x01, 0x00,
    // no explicit externdesc
     0x00,
  ]
  let comp = @component.parse_component_binary(Bytes::from_array(bytes)) catch {
    e => return fail("parse component failed: \{e}")
  }
  let import_payload = match find_component_section_payload(comp, 10) {
    Some(p) => p
    None => return fail("missing import section")
  }
  let export_payload = match find_component_section_payload(comp, 11) {
    Some(p) => p
    None => return fail("missing export section")
  }
  let imports = @component.parse_import_section(import_payload) catch {
    e => return fail("parse import section failed: \{e}")
  }
  let exports = @component.parse_export_section(export_payload) catch {
    e => return fail("parse export section failed: \{e}")
  }
  inspect(imports.length(), content="1")
  inspect(imports[0].desc, content="FuncType(0)")
  inspect(exports.length(), content="1")
  inspect(exports[0].sortidx, content="{sort: Func, idx: 0}")
  inspect(exports[0].desc, content="None")
}
