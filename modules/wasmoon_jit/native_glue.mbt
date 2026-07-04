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
pub fn plan_integration(
  func : @milkir.Function,
  machv_func : @machv.Function,
) -> JitIntegrationPlan raise @machv_emit.EmitError {
  // TODO(wasmoon_jit): select the target from the configured JIT ISA instead of defaulting to AArch64.
  plan_integration_for_target(func, machv_func, AArch64)
}
