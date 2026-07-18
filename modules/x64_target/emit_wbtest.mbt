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
