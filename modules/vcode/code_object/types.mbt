///|
#derive(Eq, Debug)
pub(all) enum Architecture {
  AArch64
  X64
}

///|
#derive(Eq, Debug)
pub(all) enum RegisterBank {
  Int
  FpVector
}

///|
#derive(Eq, Debug)
pub(all) enum RootLocation {
  Register(RegisterBank, Int32)
  Stack(offset~ : Int32, ty~ : @native.ValueType)
}

///|
#derive(Eq, Debug)
pub(all) enum UnwindOperation {
  StackAlloc(size~ : Int32)
  SetFramePointer(RegisterBank, Int32, cfa_offset~ : Int32)
  SaveRegister(RegisterBank, Int32, cfa_offset~ : Int32)
}

///|
#derive(Eq, Debug)
pub struct UnwindDirective {
  offset : Int32
  operation : UnwindOperation
}

///|
pub fn UnwindDirective::new(
  offset : Int32,
  operation : UnwindOperation,
) -> UnwindDirective {
  { offset, operation, }
}

///|
#derive(Eq, Debug)
pub(all) enum RelocationTarget {
  Code(@native.CodeSymbol)
  External(@native.ExternalSymbol)
  Data(@native.DataSymbol)
}

///|
#derive(Eq, Debug)
pub(all) enum RelocationKind {
  AArch64Call26
  AArch64Jump26
  AArch64Page21
  AArch64PageOffset12
  X64PcRelative32
  Absolute64
}

///|
#derive(Eq, Debug)
pub struct Relocation {
  offset : Int32
  kind : RelocationKind
  target : RelocationTarget
  addend : Int64
}

///|
pub fn Relocation::new(
  offset : Int32,
  kind : RelocationKind,
  target : RelocationTarget,
  addend~ : Int64 = 0L,
) -> Relocation {
  { offset, kind, target, addend, }
}

///|
#derive(Eq, Debug)
pub struct TrapSite {
  offset : Int32
  reason : @native.TrapReason
  source : @native.SourceLocation?
}

///|
pub fn TrapSite::new(
  offset : Int32,
  reason : @native.TrapReason,
  source? : @native.SourceLocation,
) -> TrapSite {
  { offset, reason, source, }
}

///|
#derive(Eq, Debug)
pub struct SourceSite {
  offset : Int32
  length : Int32
  source : @native.SourceLocation
}

///|
pub fn SourceSite::new(
  offset : Int32,
  source : @native.SourceLocation,
  length~ : Int32 = 0,
) -> SourceSite {
  { offset, length, source, }
}

///|
#derive(Eq, Debug)
pub struct SafepointSite {
  offset : Int32
  kind : @native.SafepointKind
  roots : Array[RootLocation]
  source : @native.SourceLocation?
  stack_map : @native.StackMapMetadata?
}

///|
pub fn SafepointSite::new(
  offset : Int32,
  kind : @native.SafepointKind,
  roots : Array[RootLocation],
  source? : @native.SourceLocation,
  stack_map? : @native.StackMapMetadata,
) -> SafepointSite {
  { offset, kind, roots: roots.copy(), source, stack_map, }
}

///|
#derive(Debug)
pub struct UnlinkedCodeObject {
  priv architecture : Architecture
  priv code : Array[Byte]
  priv relocations : Array[Relocation]
  priv sources : Array[SourceSite]
  priv traps : Array[TrapSite]
  priv safepoints : Array[SafepointSite]
  priv unwind : Array[UnwindDirective]
}

///|
pub fn UnlinkedCodeObject::architecture(
  self : UnlinkedCodeObject,
) -> Architecture {
  self.architecture
}

///|
pub fn UnlinkedCodeObject::sources(
  self : UnlinkedCodeObject,
) -> Array[SourceSite] {
  self.sources.copy()
}

///|
pub fn UnlinkedCodeObject::code(self : UnlinkedCodeObject) -> Array[Byte] {
  self.code.copy()
}

///|
pub fn UnlinkedCodeObject::relocations(
  self : UnlinkedCodeObject,
) -> Array[Relocation] {
  self.relocations.copy()
}

///|
pub fn UnlinkedCodeObject::traps(self : UnlinkedCodeObject) -> Array[TrapSite] {
  self.traps.copy()
}

///|
pub fn UnlinkedCodeObject::safepoints(
  self : UnlinkedCodeObject,
) -> Array[SafepointSite] {
  self.safepoints.map(site => {
    SafepointSite::new(
      site.offset,
      site.kind,
      site.roots,
      source?=site.source,
      stack_map?=site.stack_map,
    )
  })
}

///|
pub fn UnlinkedCodeObject::unwind(
  self : UnlinkedCodeObject,
) -> Array[UnwindDirective] {
  self.unwind.copy()
}
