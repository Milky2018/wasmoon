///|
priv struct ImportedWasmCallContinuation {
  func_addr : Int
  continuation : @executor.ExecutionContinuation
}

///|
/// JIT module context containing compiled module and runtime state
pub struct JITModuleContext {
  jit_module : @compiled_jit.JITModule
  // For syncing globals back to store after JIT calls
  globals_ptr : Int64
  global_addrs : Array[Int]
  // Tables owned/imported by this module instance
  table_addrs : Array[Int]
  // For converting module function indices to store addresses
  func_addrs : Array[Int]
  // Function type indices in module index space (imports + locals)
  func_type_indices : Array[Int]
  // Module canonical type indices
  canonical_type_indices : Array[Int]
  // Module-local type graph used by GC type checks
  module_types : Array[@types.SubType]
  module_rec_groups : Array[Int]
  // Whether this module uses subtype helper for call_indirect checks
  use_subtype_indirect_check : Bool
  priv async_host_drivers : Map[Int64, @runtime.AsyncHostCallDriver]
  priv async_host_errors : Map[Int64, @runtime.RuntimeError]
  priv imported_wasm_continuations : Map[Int64, ImportedWasmCallContinuation]
}

///|
pub fn JITModuleContext::JITModuleContext(
  jit_module : @compiled_jit.JITModule,
  globals_ptr : Int64,
  global_addrs : Array[Int],
  table_addrs : Array[Int],
  func_addrs : Array[Int],
  func_type_indices : Array[Int],
  canonical_type_indices : Array[Int],
  module_types : Array[@types.SubType],
  module_rec_groups : Array[Int],
  use_subtype_indirect_check : Bool,
) -> JITModuleContext {
  {
    jit_module,
    globals_ptr,
    global_addrs,
    table_addrs,
    func_addrs,
    func_type_indices,
    canonical_type_indices,
    module_types,
    module_rec_groups,
    use_subtype_indirect_check,
    async_host_drivers: Map([]),
    async_host_errors: Map([]),
    imported_wasm_continuations: Map([]),
  }
}

///|
/// Release the native module after every call and continuation has ended.
pub fn JITModuleContext::close(self : JITModuleContext) -> Unit {
  self.jit_module.close()
}
