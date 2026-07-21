///|
fn code_object_root(
  function : @vcode.Function[X64Inst],
  frame : X64Frame,
  value : @vcode.Value,
  location : @vcode.Location,
) -> @code_object.RootLocation {
  match location {
    Register(reg) => {
      let bank : @code_object.RegisterBank = match reg.class {
        Int => Int
        FpVector => FpVector
      }
      Register(bank, reg.id)
    }
    Stack(slot) =>
      Stack(
        offset=frame.slot_offset(slot).unwrap(),
        ty=function.value_type(value).unwrap(),
      )
  }
}

///|
fn record_instruction_metadata(
  buffer : CodeBuffer,
  function : @vcode.Function[X64Inst],
  allocation : @vcode.Allocation,
  frame : X64Frame,
  instruction : @vcode.Instruction,
  offset : Int,
  sources : Array[@code_object.SourceSite],
  traps : Array[@code_object.TrapSite],
  safepoints : Array[@code_object.SafepointSite],
) -> Unit {
  let metadata = function.instruction_metadata(instruction).unwrap()
  if (metadata.trap is Some(_) || metadata.safepoint is Some(_)) &&
    buffer.position() == offset {
    buffer.emit_byte(0x90)
  }
  if metadata.source is Some(source) {
    sources.push(@code_object.SourceSite::new(offset, source))
  }
  if metadata.trap is Some(reason) {
    traps.push(
      @code_object.TrapSite::new(offset, reason, source?=metadata.source),
    )
  }
  if metadata.safepoint is Some(kind) {
    let roots = allocation
      .safepoint_roots(instruction)
      .map(entry => {
        let (value, location) = entry
        code_object_root(function, frame, value, location)
      })
    safepoints.push(
      @code_object.SafepointSite::new(
        offset,
        kind,
        roots,
        source?=metadata.source,
        stack_map?=metadata.stack_map,
      ),
    )
  }
}
