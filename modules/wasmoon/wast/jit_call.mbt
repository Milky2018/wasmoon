///|
/// Structured failure while invoking a prepared JIT module context.
pub(all) suberror JITCoreCallError {
  FunctionUnavailable(Int)
  ArgumentTypeMismatch(Int)
  ResultTypeMismatch(Int)
  Trap(String)
  Cancelled
  Exit(Int)
  GcSetupFailed(String)
} derive(Debug, Eq)

///|
pub impl Show for JITCoreCallError with fn output(self, logger) {
  logger.write_string(@types.compact_show_repr(to_repr(self).to_string()))
}

///|
fn encode_jit_entry_args(
  args : Array[@types.Value],
  param_types : Array[@types.ValueType],
  jit_module : @jit.JITModule,
  instance : @runtime.ModuleInstance,
) -> Array[Int64] raise JITCoreCallError {
  if args.length() != param_types.length() {
    raise ArgumentTypeMismatch(args.length())
  }
  let slots : Array[Int64] = []
  for i, ty in param_types {
    match encode_value(ty, args[i], jit_module, instance) {
      Some(encoded) =>
        for raw in encoded {
          slots.push(raw)
        }
      None => raise ArgumentTypeMismatch(i)
    }
  }
  slots
}

///|
fn decode_jit_entry_results(
  results : Array[Int64],
  result_types : Array[@types.ValueType],
  store : @runtime.Store,
  jit_module : @jit.JITModule,
  instance : @runtime.ModuleInstance,
) -> Array[@types.Value] raise JITCoreCallError {
  let values : Array[@types.Value] = []
  let mut slot = 0
  for i, ty in result_types {
    let needed = if ty is V128 { 2 } else { 1 }
    if slot + needed > results.length() {
      raise ResultTypeMismatch(i)
    }
    let value : @types.Value = match ty {
      I32 => I32(@types.FromInt64::from_int64_bits(results[slot]))
      I64 => I64(@types.FromInt64::from_int64_bits(results[slot]))
      F32 => F32(@types.FromInt64::from_int64_bits(results[slot]))
      F64 => F64(@types.FromInt64::from_int64_bits(results[slot]))
      V128 =>
        V128(@types.int64_pair_to_v128_le(results[slot], results[slot + 1]))
      _ => decode_ref_value(ty, results[slot], store, jit_module, instance)
    }
    values.push(value)
    slot = slot + needed
  }
  if slot != results.length() {
    raise ResultTypeMismatch(result_types.length())
  }
  values
}

///|
/// Invoke one function through a prepared JIT module context.
///
/// This is the shared entry-call seam used by WAST and component adapters. It
/// keeps globals and tables coherent with interpreter-visible store state and
/// scopes the C-heap registration to the native invocation.
pub fn JITModuleContext::call_core_func(
  self : JITModuleContext,
  store : @runtime.Store,
  instance : @runtime.ModuleInstance,
  func_idx : Int,
  args : Array[@types.Value],
) -> Array[@types.Value] raise JITCoreCallError {
  guard self.jit_module.get_func(func_idx) is Some(func) else {
    raise FunctionUnavailable(func_idx)
  }
  let encoded_args = encode_jit_entry_args(
    args,
    func.param_types,
    self.jit_module,
    instance,
  )
  sync_store_globals_to_jit(self, store)
  sync_tables_to_jit(
    instance,
    store,
    self.jit_module,
    use_subtype_indirect_check=self.use_subtype_indirect_check,
  )
  let mut gc_active = false
  defer {
    if gc_active {
      @wasmoon_jit.gc_teardown(self.jit_module.get_context_ptr())
    }
    sync_jit_globals_to_store(self, store)
    sync_jit_tables_to_store(self, store)
  }
  match store.c_heap {
    Some(heap) => {
      @wasmoon_jit.gc_setup(
        heap,
        self.module_types,
        self.canonical_type_indices,
        ctx_ptr=self.jit_module.get_context_ptr(),
        func_type_indices=self.func_type_indices,
        func_table_ptr=self.jit_module.get_func_table_ptr(),
        num_funcs=self.jit_module.get_func_count(),
      ) catch {
        error => raise GcSetupFailed(error.to_string())
      }
      gc_active = true
      self.jit_module.set_gc_heap(heap.get_ptr())
    }
    None => ()
  }
  let raw_results = self.jit_module.call_with_context(func, encoded_args) catch {
    JITTrap(message) => raise Trap(message)
    JITCancelled => raise Cancelled
    JITExit(code) => raise Exit(code)
  }
  decode_jit_entry_results(
    raw_results,
    func.result_types,
    store,
    self.jit_module,
    instance,
  )
}
