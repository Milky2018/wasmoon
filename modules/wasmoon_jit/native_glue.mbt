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
  native_glue : Array[NativeGlueBinding]
  object : @machv_emit.CodeObject
} derive(Debug)

///|
pub fn default_native_glue() -> Array[NativeGlueBinding] {
  // TODO(wasmoon_jit): point these records at the moved jit_ffi C/assembly
  // sources after the legacy JIT package is rehomed under wasmoon_jit.
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
pub fn plan_integration(
  func : @milkir.Function,
  machv_func : @machv.Function,
) -> JitIntegrationPlan {
  {
    entry_symbol: func.name,
    native_glue: default_native_glue(),
    object: @machv_emit.emit_function(machv_func),
  }
}
