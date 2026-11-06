///|
#valtype
pub struct CodeSites {
  priv sources : Array[@code_object.SourceSite]
  priv traps : Array[@code_object.TrapSite]
  priv safepoints : Array[@code_object.SafepointSite]
}

///|
pub fn CodeSites::new() -> CodeSites {
  { sources: [], traps: [], safepoints: [], }
}

///|
fn[Inst] code_object_root(
  function : Function[Inst],
  frame : FrameLayout,
  value : Value,
  location : Location,
) -> @code_object.RootLocation {
  match location {
    Register(reg) => {
      let bank : @code_object.RegisterBank = match reg.class {
        Int => Int
        Float | Vector | FpVector => FpVector
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
pub fn[Inst] CodeSites::record(
  self : CodeSites,
  function : Function[Inst],
  allocation : Allocation,
  frame : FrameLayout,
  instruction : Instruction,
  metadata : InstructionAnnotations,
  offset : Int32,
  end : Int32,
) -> Unit {
  if metadata.source() is Some(source) {
    let length = end - offset
    if length > 0 {
      if self.sources.last() is Some(previous) &&
        previous.source == source &&
        previous.offset + previous.length == offset {
        self.sources[self.sources.length() - 1] = @code_object.SourceSite::new(
          previous.offset,
          source,
          length=previous.length + length,
        )
      } else {
        self.sources.push(@code_object.SourceSite::new(offset, source, length~))
      }
    }
  }
  if metadata.trap() is Some(reason) {
    self.traps.push(
      @code_object.TrapSite::new(offset, reason, source?=metadata.source()),
    )
  }
  if metadata.safepoint() is Some(kind) {
    let roots = allocation
      .safepoint_roots(instruction)
      .map(entry => {
        let (value, location) = entry
        code_object_root(function, frame, value, location)
      })
    self.safepoints.push(
      @code_object.SafepointSite::new(
        offset,
        kind,
        roots,
        source?=metadata.source(),
        stack_map?=metadata.stack_map(),
      ),
    )
  }
}

///|
pub fn CodeSites::build(
  self : CodeSites,
  architecture : @code_object.Architecture,
  code : Array[Byte],
  relocations : Array[@code_object.Relocation],
  unwind : Array[@code_object.UnwindDirective],
) -> @code_object.UnlinkedCodeObject raise @code_object.CodeObjectVerifyError {
  @code_object.build(
    architecture,
    code,
    relocations~,
    sources=self.sources,
    traps=self.traps,
    safepoints=self.safepoints,
    unwind~,
  )
}
