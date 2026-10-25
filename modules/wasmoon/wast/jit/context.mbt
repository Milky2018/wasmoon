///|
priv struct ImportedWasmCallContinuation {
  func_addr : Int32
  continuation : @executor.ExecutionContinuation
}

///|
/// JIT module context containing compiled module and runtime state
pub struct JITModuleContext {
  jit_module : @compiled_jit.JITModule
  // For syncing globals back to store after JIT calls
  globals_ptr : Int64
  global_addrs : ReadOnlyArray[Int32]
  // Tables owned/imported by this module instance
  table_addrs : ReadOnlyArray[Int32]
  // For converting module function indices to store addresses
  func_addrs : ReadOnlyArray[Int32]
  // Function type indices in module index space (imports + locals)
  func_type_indices : ReadOnlyArray[Int32]
  // Module canonical type indices
  canonical_type_indices : ReadOnlyArray[Int32]
  // Module-local type graph used by GC type checks
  module_types : ReadOnlyArray[@types.SubType]
  module_rec_groups : ReadOnlyArray[Int32]
  // Whether this module uses subtype helper for call_indirect checks
  use_subtype_indirect_check : Bool
  priv mut gc_environment : @wasmoon_jit.PreparedGCEnvironment?
  priv mut owner : @runtime.ModuleInstance?
  priv async_host_drivers : Map[Int64, @runtime.AsyncHostCallDriver]
  priv async_host_errors : Map[Int64, @runtime.RuntimeError]
  priv imported_wasm_continuations : Map[Int64, ImportedWasmCallContinuation]
}

///|
pub fn JITModuleContext::JITModuleContext(
  jit_module : @compiled_jit.JITModule,
  globals_ptr : Int64,
  global_addrs : ArrayView[Int32],
  table_addrs : ArrayView[Int32],
  func_addrs : ArrayView[Int32],
  func_type_indices : ArrayView[Int32],
  canonical_type_indices : ArrayView[Int32],
  module_types : ArrayView[@types.SubType],
  module_rec_groups : ArrayView[Int32],
  use_subtype_indirect_check : Bool,
) -> JITModuleContext {
  {
    jit_module,
    globals_ptr,
    global_addrs: ReadOnlyArray::from_array(global_addrs),
    table_addrs: ReadOnlyArray::from_array(table_addrs),
    func_addrs: ReadOnlyArray::from_array(func_addrs),
    func_type_indices: ReadOnlyArray::from_array(func_type_indices),
    canonical_type_indices: ReadOnlyArray::from_array(canonical_type_indices),
    module_types: ReadOnlyArray::from_array(module_types),
    module_rec_groups: ReadOnlyArray::from_array(module_rec_groups),
    use_subtype_indirect_check,
    gc_environment: None,
    owner: None,
    async_host_drivers: Map([]),
    async_host_errors: Map([]),
    imported_wasm_continuations: Map([]),
  }
}

///|
/// Release the native module after every call and continuation has ended.
pub fn JITModuleContext::close(self : JITModuleContext) -> Unit {
  self.jit_module.close()
  self.gc_environment = None
}

///|
/// One native context belongs to one live Store instance, even if an integer
/// instance index is reused after rollback or in another Store.
pub fn JITModuleContext::bind_instance(
  self : JITModuleContext,
  store : @runtime.Store,
  instance : @runtime.ModuleInstance,
) -> Unit raise @runtime.RuntimeError {
  store.check_instance(instance)
  guard self.func_addrs == instance.func_addrs &&
    self.global_addrs == instance.global_addrs &&
    self.table_addrs == instance.table_addrs &&
    self.func_type_indices == instance.func_type_indices else {
    raise InvalidHandle
  }
  if self.owner is Some(original) {
    store.check_instance(original)
    guard physical_equal(original, instance) else { raise InvalidHandle }
  } else {
    self.owner = Some(instance)
  }
}
