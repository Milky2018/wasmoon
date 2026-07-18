///|
test "x64 pairwise i16 add uses horizontal lane semantics" {
  let buffer = CodeBuffer::new()
  buffer.x86_emit_phaddw_xmm_xmm(2, 1)
  debug_inspect(
    buffer.code,
    content=(
      #|[0x66, 0x0f, 0x38, 0x01, 0xd1]
    ),
  )
}

///|
test "x64 stack allocation probes every guard-page interval" {
  let buffer = CodeBuffer::new()
  emit_sp_adjust(buffer, true, 8192)
  debug_inspect(
    buffer.code,
    content=(
      #|[
      #|  0x48,
      #|  0x81,
      #|  0xec,
      #|  0x00,
      #|  0x10,
      #|  0x00,
      #|  0x00,
      #|  0x4c,
      #|  0x8b,
      #|  0x94,
      #|  0x24,
      #|  0x00,
      #|  0x00,
      #|  0x00,
      #|  0x00,
      #|  0x48,
      #|  0x81,
      #|  0xec,
      #|  0x00,
      #|  0x10,
      #|  0x00,
      #|  0x00,
      #|  0x4c,
      #|  0x8b,
      #|  0x94,
      #|  0x24,
      #|  0x00,
      #|  0x00,
      #|  0x00,
      #|  0x00,
      #|]
    ),
  )
}
