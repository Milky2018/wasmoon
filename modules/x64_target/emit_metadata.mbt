///|
fn record_instruction_metadata(
  buffer : CodeBuffer,
  function : @vcode.Function[X64Inst],
  allocation : @vcode.Allocation,
  frame : X64Frame,
  instruction : @vcode.Instruction,
  offset : Int32,
  sites : @vcode.CodeSites,
) -> Unit {
  let metadata = function.instruction_annotations(instruction).unwrap()
  if (metadata.trap() is Some(_) || metadata.safepoint() is Some(_)) &&
    buffer.position() == offset {
    buffer.emit_byte(0x90)
  }
  sites.record(
    function,
    allocation,
    frame.layout,
    instruction,
    metadata,
    offset,
    buffer.position(),
  )
}
