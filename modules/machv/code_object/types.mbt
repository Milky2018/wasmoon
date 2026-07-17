///|
pub(all) enum Architecture {
  AArch64
  X64
} derive(Eq, Debug)

///|
pub(all) enum RegisterBank {
  Int
  FpVector
} derive(Eq, Debug)

///|
pub(all) enum RootLocation {
  Register(RegisterBank, Int)
  Stack(offset~ : Int, ty~ : @semantic.ValueType)
} derive(Eq, Debug)

///|
pub(all) enum RelocationTarget {
  Code(@semantic.CodeSymbol)
  External(@semantic.ExternalSymbol)
  Data(@semantic.DataSymbol)
} derive(Eq, Debug)

///|
pub(all) enum RelocationKind {
  AArch64Call26
  AArch64Jump26
  AArch64Page21
  AArch64PageOffset12
  X64PcRelative32
  Absolute64
} derive(Eq, Debug)

///|
pub struct Relocation {
  offset : Int
  kind : RelocationKind
  target : RelocationTarget
  addend : Int64
} derive(Eq, Debug)

///|
pub fn Relocation::new(
  offset : Int,
  kind : RelocationKind,
  target : RelocationTarget,
  addend? : Int64 = 0L,
) -> Relocation {
  { offset, kind, target, addend }
}

///|
pub struct TrapSite {
  offset : Int
  reason : @semantic.TrapReason
  source : @semantic.SourceLocation?
} derive(Eq, Debug)

///|
pub fn TrapSite::new(
  offset : Int,
  reason : @semantic.TrapReason,
  source? : @semantic.SourceLocation,
) -> TrapSite {
  { offset, reason, source }
}

///|
pub struct SourceSite {
  offset : Int
  source : @semantic.SourceLocation
} derive(Eq, Debug)

///|
pub fn SourceSite::new(
  offset : Int,
  source : @semantic.SourceLocation,
) -> SourceSite {
  { offset, source }
}

///|
pub struct SafepointSite {
  offset : Int
  kind : @semantic.SafepointKind
  roots : Array[RootLocation]
  source : @semantic.SourceLocation?
} derive(Eq, Debug)

///|
pub fn SafepointSite::new(
  offset : Int,
  kind : @semantic.SafepointKind,
  roots : Array[RootLocation],
  source? : @semantic.SourceLocation,
) -> SafepointSite {
  { offset, kind, roots: roots.copy(), source }
}

///|
pub struct UnlinkedCodeObject {
  priv architecture : Architecture
  priv code : Array[Byte]
  priv relocations : Array[Relocation]
  priv sources : Array[SourceSite]
  priv traps : Array[TrapSite]
  priv safepoints : Array[SafepointSite]
  priv unwind : Array[Byte]
} derive(Debug)

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
    SafepointSite::new(site.offset, site.kind, site.roots, source?=site.source)
  })
}

///|
pub fn UnlinkedCodeObject::unwind(self : UnlinkedCodeObject) -> Array[Byte] {
  self.unwind.copy()
}
