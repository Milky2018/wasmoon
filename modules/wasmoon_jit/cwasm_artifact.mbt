///|
pub(all) struct CwasmFunctionRecord {
  function_index : Int
  code_offset : Int
  code_size : Int
} derive(Eq, Debug)

///|
pub(all) struct CwasmArtifact {
  version : Int
  code : Array[Int]
  functions : Array[CwasmFunctionRecord]
  runtime_relocations : Array[ResolvedRuntimeRelocation]
  block_fixups : Array[@machv_emit.Fixup]
  stack_maps : Array[@machv_emit.StackMap]
  debug_entries : Array[@machv_emit.DebugEntry]
} derive(Debug)

///|
pub fn CwasmArtifact::from_linked_code(
  linked : LinkedCode,
  function_index : Int,
) -> CwasmArtifact {
  {
    version: 1,
    code: linked.code,
    functions: [
      { function_index, code_offset: 0, code_size: linked.code.length() },
    ],
    runtime_relocations: linked.runtime_relocations,
    block_fixups: linked.block_fixups,
    stack_maps: linked.stack_maps,
    debug_entries: linked.debug_entries,
  }
}

///|
pub fn CwasmArtifact::manifest(self : CwasmArtifact) -> Array[String] {
  // TODO(wasmoon_jit): replace this manifest helper with the final .cwasm
  // binary reader/writer after the legacy cwasm package is physically moved.
  [
    "cwasm.version=" + self.version.to_string(),
    "cwasm.code_size=" + self.code.length().to_string(),
    "cwasm.functions=" + self.functions.length().to_string(),
    "cwasm.runtime_relocations=" + self.runtime_relocations.length().to_string(),
    "cwasm.block_fixups=" + self.block_fixups.length().to_string(),
  ]
}
