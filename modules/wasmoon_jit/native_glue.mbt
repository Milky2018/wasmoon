///|
pub(all) enum NativeGlueKind {
  ExecutableMemory
  TrapHandler
  StackSwitch
  HostCallBridge
  WasmMemoryOp
  GcRuntime
  ExceptionHandling
  WasiPreview1
  DebugInfo
} derive(Eq, Debug)

///|
pub(all) struct NativeGlueBinding {
  kind : NativeGlueKind
  symbol : String
  sources : Array[String]
} derive(Eq, Debug)

///|
pub(all) struct JitIntegrationPlan {
  entry_symbol : String
  target : @machv_emit.EmitTarget
  native_glue : Array[NativeGlueBinding]
  object : @machv_emit.MachineCode
}

///|
pub suberror JitPipelineError {
  PipelineFailure(message~ : String)
} derive(Debug, Eq)

///|
pub impl Show for JitPipelineError with fn output(self, logger) {
  logger.write_string(to_repr(self).to_string())
}

///|
pub fn jit_ffi_native_stub_sources() -> Array[String] {
  [
    "jit.c", "trap.c", "exec_mem.c", "jit_context.c", "memory_ops.c", "segment_ops.c",
    "gc_type_cache.c", "gc_ops.c", "gc_allocator.c", "gc_heap.c", "exception.c",
    "wasi.c", "wasm_stack.c", "trampoline_call_x86_64.S", "stack_switch_aarch64.S",
    "stack_switch_x86_64.S", "dwarf.c",
  ]
}

///|
pub fn default_native_glue() -> Array[NativeGlueBinding] {
  [
    {
      kind: ExecutableMemory,
      symbol: "wasmoon_jit_exec_mem",
      sources: ["exec_mem.c"],
    },
    { kind: TrapHandler, symbol: "wasmoon_jit_trap", sources: ["trap.c"] },
    {
      kind: StackSwitch,
      symbol: "wasmoon_jit_stack_switch",
      sources: [
        "wasm_stack.c", "trampoline_call_x86_64.S", "stack_switch_aarch64.S", "stack_switch_x86_64.S",
      ],
    },
    {
      kind: HostCallBridge,
      symbol: "wasmoon_jit_hostcall",
      sources: ["jit.c", "jit_context.c"],
    },
    {
      kind: WasmMemoryOp,
      symbol: "wasmoon_jit_memory_op",
      sources: ["memory_ops.c", "segment_ops.c"],
    },
    {
      kind: GcRuntime,
      symbol: "wasmoon_jit_gc",
      sources: ["gc_type_cache.c", "gc_ops.c", "gc_allocator.c", "gc_heap.c"],
    },
    {
      kind: ExceptionHandling,
      symbol: "wasmoon_jit_exception",
      sources: ["exception.c"],
    },
    { kind: WasiPreview1, symbol: "wasmoon_jit_wasi", sources: ["wasi.c"] },
    { kind: DebugInfo, symbol: "wasmoon_jit_dwarf", sources: ["dwarf.c"] },
  ]
}

///|
pub fn native_glue_covers_source(
  glue : Array[NativeGlueBinding],
  source : String,
) -> Bool {
  for binding in glue {
    for owned in binding.sources {
      if owned == source {
        return true
      }
    }
  }
  false
}

///|
pub fn native_glue_covers_jit_ffi_stubs(
  glue? : Array[NativeGlueBinding] = default_native_glue(),
) -> Bool {
  for source in jit_ffi_native_stub_sources() {
    if !native_glue_covers_source(glue, source) {
      return false
    }
  }
  true
}

///|
pub fn plan_integration_for_target(
  func : @milkir.Function,
  machv_func : @machv.Function,
  regalloc_output : @machv_regalloc.Output,
  target : @machv_emit.EmitTarget,
) -> JitIntegrationPlan raise JitPipelineError {
  let isa = emit_target_to_isa(target)
  let embedding_abi = wasm_embedding_abi_for_isa(isa)
  let object = @machv_emit.emit_function_with_regalloc(
    machv_func,
    regalloc_output,
    isa~,
    embedding_abi=Some(embedding_abi),
  ) catch {
    err => raise PipelineFailure(message=err.to_string())
  }
  {
    entry_symbol: func.name,
    target,
    native_glue: default_native_glue(),
    object,
  }
}

///|
pub fn emit_target_to_isa(target : @machv_emit.EmitTarget) -> @isa.ISA {
  match target {
    AArch64 => AArch64
    X64 => AMD64
  }
}

///|
pub fn lower_milkir_for_target(
  func : @milkir.Function,
  target : @machv_emit.EmitTarget,
) -> @machv.Function raise JitPipelineError {
  let isa = emit_target_to_isa(target)
  let embedding_abi = wasm_embedding_abi_for_isa(isa)
  lower_semantic_core_with_isa(func, isa, embedding_abi)
}

///|
pub fn lower_wasm_body_milkir_for_target(
  func : @milkir.Function,
  target : @machv_emit.EmitTarget,
  use_subtype_indirect_check? : Bool = true,
  canonical_type_indices? : Array[Int] = [],
) -> @machv.Function raise JitPipelineError {
  let isa = emit_target_to_isa(target)
  let embedding_abi = wasm_embedding_abi_for_isa(isa)
  lower_semantic_wasm_with_isa(
    func, isa, embedding_abi, use_subtype_indirect_check, canonical_type_indices,
  )
}

///|
pub fn lower_wasm_body_milkir_with_isa(
  func : @milkir.Function,
  isa : @isa.ISA,
  use_subtype_indirect_check? : Bool = true,
  canonical_type_indices? : Array[Int] = [],
) -> @machv.Function raise JitPipelineError {
  lower_semantic_wasm_with_isa(
    func,
    isa,
    wasm_embedding_abi_for_isa(isa),
    use_subtype_indirect_check,
    canonical_type_indices,
  )
}

///|
pub fn plan_milkir_integration_for_target(
  func : @milkir.Function,
  target : @machv_emit.EmitTarget,
) -> JitIntegrationPlan raise JitPipelineError {
  let isa = emit_target_to_isa(target)
  let embedding_abi = wasm_embedding_abi_for_isa(isa)
  let machv_func = lower_semantic_core_with_isa(func, isa, embedding_abi)
  let (allocated_func, output) = @machv_regalloc.allocate_registers_backtracking_output_with_isa(
    machv_func,
    isa,
    embedding_abi=Some(embedding_abi),
  ) catch {
    err => raise PipelineFailure(message=err.to_string())
  }
  plan_integration_for_target(func, allocated_func, output, target)
}

///|
pub fn plan_wasm_body_milkir_integration_for_target(
  func : @milkir.Function,
  target : @machv_emit.EmitTarget,
) -> JitIntegrationPlan raise JitPipelineError {
  let isa = emit_target_to_isa(target)
  let embedding_abi = wasm_embedding_abi_for_isa(isa)
  let machv_func = lower_semantic_wasm_with_isa(
    func,
    isa,
    embedding_abi,
    true,
    [],
  )
  let (allocated_func, output) = @machv_regalloc.allocate_registers_backtracking_output_with_isa(
    machv_func,
    isa,
    embedding_abi=Some(embedding_abi),
  ) catch {
    err => raise PipelineFailure(message=err.to_string())
  }
  plan_integration_for_target(func, allocated_func, output, target)
}
