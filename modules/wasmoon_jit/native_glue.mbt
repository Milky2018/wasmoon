///|
pub(all) enum NativeGlueKind {
  ExecutableMemory
  TrapHandler
  StackSwitch
  HostCallBridge
  WasmMemoryOp
  WasiPreview1
} derive(Eq, Debug)

///|
pub(all) struct NativeGlueBinding {
  kind : NativeGlueKind
  symbol : String
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
pub fn default_native_glue() -> Array[NativeGlueBinding] {
  // TODO(wasmoon_jit): replace these manifest records with direct ownership
  // checks over the moved jit_ffi C/assembly sources.
  [
    { kind: ExecutableMemory, symbol: "wasmoon_jit_exec_mem" },
    { kind: TrapHandler, symbol: "wasmoon_jit_trap" },
    { kind: StackSwitch, symbol: "wasmoon_jit_stack_switch" },
    { kind: HostCallBridge, symbol: "wasmoon_jit_hostcall" },
    { kind: WasmMemoryOp, symbol: "wasmoon_jit_memory_op" },
    { kind: WasiPreview1, symbol: "wasmoon_jit_wasi_preview1" },
  ]
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
) -> Array[@machv.PReg] {
  match target {
    AArch64 => @aarch64_target.allocatable_regs()
    X64 => @x64_target.allocatable_regs()
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
      allocatable_regs_for_target(target),
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
      allocatable_regs_for_target(target),
    )
    |> ignore
    // TODO(ISS-022): install emitted CodeObject bytes through jit_ffi and
    // replace the legacy VCode JIT execution path end-to-end.
    plan_integration_for_target(func, machv_func, target)
  } catch {
    err => raise PipelineFailure(message=to_repr(err).to_string())
  }
}
