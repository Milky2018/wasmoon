///|
/// Mutable code and metadata exchanged by compiler stages. Verification applies
/// only to the current contents; mutation requires revalidation before use.
/// Unlike UnlinkedCodeObject, this record does not promise an immutable snapshot.
pub(all) struct CodeData {
  architecture : Architecture
  code : Array[Byte]
  relocations : Array[Relocation]
  sources : Array[SourceSite]
  traps : Array[TrapSite]
  safepoints : Array[SafepointSite]
  unwind : Array[UnwindDirective]
}

///|
/// Copy and verify an independent immutable snapshot of this data.
pub fn CodeData::freeze(
  self : CodeData,
) -> UnlinkedCodeObject raise CodeObjectVerifyError {
  build(
    self.architecture,
    self.code,
    relocations=self.relocations,
    sources=self.sources,
    traps=self.traps,
    safepoints=self.safepoints,
    unwind=self.unwind,
  )
}

///|
/// Trim builder over-allocation before retaining this data as a final artifact.
/// Does not change values or validation status.
pub fn CodeData::shrink_to_fit(self : CodeData) -> Unit {
  self.code.shrink_to_fit()
  self.relocations.shrink_to_fit()
  self.sources.shrink_to_fit()
  self.traps.shrink_to_fit()
  self.safepoints.shrink_to_fit()
  self.unwind.shrink_to_fit()
}
