///|
pub(all) struct CwasmFunctionRecord {
  function_index : Int
  code_offset : Int
  code_size : Int
} derive(Eq, Debug)

///|
pub(all) struct CwasmArtifact {
  version : Int
  target : @cwasm.TargetArch
  entry_symbol : String
  code : Array[Int]
  functions : Array[CwasmFunctionRecord]
  runtime_relocations : Array[ResolvedRuntimeRelocation]
  block_fixups : Array[@machv_emit.Fixup]
  stack_maps : Array[@machv_emit.StackMap]
  debug_entries : Array[@machv_emit.DebugEntry]
} derive(Debug)

///|
fn emit_target_to_cwasm_target(
  target : @machv_emit.EmitTarget,
) -> @cwasm.TargetArch {
  match target {
    X64 => X86_64
    AArch64 => AArch64
  }
}

///|
fn cwasm_target_name(target : @cwasm.TargetArch) -> String {
  match target {
    Unknown => "unknown"
    X86_64 => "x86_64"
    AArch64 => "aarch64"
  }
}

///|
pub fn CwasmArtifact::from_linked_code_for_target(
  linked : LinkedCode,
  function_index : Int,
  target : @cwasm.TargetArch,
  entry_symbol : String,
) -> CwasmArtifact {
  {
    version: 1,
    target,
    entry_symbol,
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
pub fn CwasmArtifact::from_jit_plan(
  plan : JitIntegrationPlan,
  resolver : RuntimeSymbolResolver,
  function_index : Int,
) -> CwasmArtifact raise LinkError {
  CwasmArtifact::from_linked_code_for_target(
    link_code_object(plan.object, resolver),
    function_index,
    emit_target_to_cwasm_target(plan.target),
    plan.entry_symbol,
  )
}

///|
fn CwasmArtifact::function_code(
  self : CwasmArtifact,
  record : CwasmFunctionRecord,
) -> Array[Int] {
  let out : Array[Int] = []
  let end = record.code_offset + record.code_size
  for i in record.code_offset..<end {
    out.push(self.code[i])
  }
  out
}

///|
pub fn CwasmArtifact::to_precompiled_module(
  self : CwasmArtifact,
) -> @cwasm.PrecompiledModule {
  let module_ = @cwasm.PrecompiledModule::new(self.target)
  for record in self.functions {
    // TODO(wasmoon_jit): carry real per-function names, signatures, frame
    // sizes, fixups, and GC stack maps from the production JIT pipeline.
    module_.add_function(
      @cwasm.CompiledEntry::new(
        record.function_index,
        self.entry_symbol,
        self.function_code(record),
        0,
        0,
        0,
        0,
      ),
    )
  }
  module_
}

///|
pub fn CwasmArtifact::serialize(self : CwasmArtifact) -> Array[Int] {
  self.to_precompiled_module().serialize()
}

///|
pub fn CwasmArtifact::manifest(self : CwasmArtifact) -> Array[String] {
  [
    "cwasm.version=" + self.version.to_string(),
    "cwasm.target=" + cwasm_target_name(self.target),
    "cwasm.code_size=" + self.code.length().to_string(),
    "cwasm.functions=" + self.functions.length().to_string(),
    "cwasm.runtime_relocations=" + self.runtime_relocations.length().to_string(),
    "cwasm.block_fixups=" + self.block_fixups.length().to_string(),
    "cwasm.serialized_size=" + self.serialize().length().to_string(),
  ]
}
