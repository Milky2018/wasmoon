///|
fn record_instruction_metadata(
  buffer : CodeBuffer,
  function : @vcode.Function[AArch64Inst],
  allocation : @vcode.Allocation,
  frame : AArch64Frame,
  instruction : @vcode.Instruction,
  offset : Int32,
  sites : @vcode.CodeSites,
) -> Unit {
  let metadata = function.instruction_annotations(instruction).unwrap()
  if (metadata.trap() is Some(_) || metadata.safepoint() is Some(_)) &&
    buffer.position() == offset {
    buffer.emit_word(0xD503201FU)
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
