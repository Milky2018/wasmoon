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
  object : @machv_emit.CodeObject
} derive(Debug)

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
  target : @machv_emit.EmitTarget,
) -> JitIntegrationPlan raise @machv_emit.EmitError {
  {
    entry_symbol: func.name,
    target,
    native_glue: default_native_glue(),
    object: @machv_emit.emit_function_for_target(machv_func, target),
  }
}

///|
pub fn lower_milkir_for_target(
  func : @milkir.Function,
  target : @machv_emit.EmitTarget,
) -> @machv.Function {
  match target {
    AArch64 => @aarch64_target.lower_function(func)
    X64 => @x64_target.lower_function(func)
  }
}

///|
pub fn lower_wasm_body_milkir_for_target(
  func : @milkir.Function,
  target : @machv_emit.EmitTarget,
) -> @machv.Function {
  match target {
    AArch64 => @aarch64_target.lower_wasm_body_function(func)
    X64 => @x64_target.lower_wasm_body_function(func)
  }
}

///|
fn allocatable_regs_for_target(
  target : @machv_emit.EmitTarget,
  reserve_extra_results_ptr? : Bool = false,
) -> Array[@machv.PReg] {
  match target {
    AArch64 => @aarch64_target.allocatable_regs(reserve_extra_results_ptr~)
    X64 => @x64_target.allocatable_regs(reserve_extra_results_ptr~)
  }
}

///|
pub fn plan_milkir_integration_for_target(
  func : @milkir.Function,
  target : @machv_emit.EmitTarget,
) -> JitIntegrationPlan raise JitPipelineError {
  let machv_func = lower_milkir_for_target(func, target)
  try {
    @machv_regalloc.allocate_and_apply(
      machv_func,
      allocatable_regs_for_target(target, reserve_extra_results_ptr=true),
    )
    |> ignore
    // TODO(wasmoon_jit): install emitted CodeObject bytes through jit_ffi and
    // replace the legacy VCode JIT execution path end-to-end.
    plan_integration_for_target(func, machv_func, target)
  } catch {
    err => raise PipelineFailure(message=to_repr(err).to_string())
  }
}

///|
pub fn plan_wasm_body_milkir_integration_for_target(
  func : @milkir.Function,
  target : @machv_emit.EmitTarget,
) -> JitIntegrationPlan raise JitPipelineError {
  let machv_func = lower_wasm_body_milkir_for_target(func, target)
  try {
    @machv_regalloc.allocate_and_apply(
      machv_func,
      allocatable_regs_for_target(target, reserve_extra_results_ptr=true),
    )
    |> ignore
    // TODO(ISS-026): install emitted CodeObject bytes through jit_ffi and
    // replace the legacy VCode JIT execution path end-to-end.
    plan_integration_for_target(func, machv_func, target)
  } catch {
    err => raise PipelineFailure(message=to_repr(err).to_string())
  }
}
