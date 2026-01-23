///|
test "component: sniff_binary_kind recognizes core module vs component" {
  let core : Array[Byte] = [0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00]
  inspect(
    @component.sniff_binary_kind(Bytes::from_array(core)),
    content="Some(CoreModule)",
  )
  let component : Array[Byte] = [
    0x00, 0x61, 0x73, 0x6d,
    // version=u16(0x0d), layer=u16(0x01)
     0x0d, 0x00, 0x01, 0x00,
  ]
  inspect(
    @component.sniff_binary_kind(Bytes::from_array(component)),
    content="Some(Component)",
  )
}

///|
test "component: sniff_binary_kind rejects non-wasm and short inputs" {
  let short : Array[Byte] = [0x00, 0x61, 0x73]
  inspect(
    @component.sniff_binary_kind(Bytes::from_array(short)),
    content="None",
  )
  let not_wasm : Array[Byte] = [0x01, 0x02, 0x03, 0x04, 0x01, 0x00, 0x00, 0x00]
  inspect(
    @component.sniff_binary_kind(Bytes::from_array(not_wasm)),
    content="None",
  )
}
