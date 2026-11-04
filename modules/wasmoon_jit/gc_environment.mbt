///|
fn validate_gc_setup(
  context : JITContext,
  func_type_count : Int32,
  func_table_ptr : Int64,
  num_funcs : Int32,
) -> Unit raise GCSetupError {
  if c_jit_context_is_valid(context) == 0 {
    raise MissingJITContext
  }
  if num_funcs < 0 {
    raise InvalidFuncCount(num_funcs~)
  }
  if func_type_count != num_funcs {
    raise FuncTypeIndicesLengthMismatch(
      func_type_indices_len=func_type_count,
      num_funcs~,
    )
  }
  if num_funcs > 0 && func_table_ptr == 0L {
    raise MissingFunctionTableContext(num_funcs~)
  }
}

///|
/// Immutable module metadata for repeated binding to one native context.
/// Preparation snapshots type mappings and native function addresses. Code must
/// outlive this environment; prepare again after changing the function table.
/// Heap/root/execution state is deliberately not captured here.
pub struct PreparedGCEnvironment {
  priv context : JITContext
  priv types : FixedArray[Int32]
  priv canonical : FixedArray[Int32]
  priv functions : FixedArray[Int32]
  priv addresses : FixedArray[Int64]
}

///|
/// Freeze metadata once after installing the context's complete function table.
pub fn NativeJITContext::prepare_gc_environment(
  self : NativeJITContext,
  types : ArrayView[@types.SubType],
  canonical_indices : ArrayView[Int32],
  func_type_indices : ArrayView[Int32],
) -> PreparedGCEnvironment raise GCSetupError {
  let count = context_func_count(self.handle)
  let table = context_func_table_ptr(self.handle)
  validate_gc_setup(self.handle, func_type_indices.length(), table, count)
  {
    context: self.handle,
    types: gc_type_data(types),
    canonical: FixedArray::makei(canonical_indices.length(), i => {
      canonical_indices[i]
    }),
    functions: FixedArray::makei(func_type_indices.length(), i => {
      func_type_indices[i]
    }),
    addresses: @jit_ffi.snapshot_function_addresses(table, count),
  }
}

///|
/// Restore every binding outside guest execution, even after another binding
/// replaced or cleared it. Native views retain these same immutable payloads.
pub fn NativeJITContext::setup_gc_environment(
  self : NativeJITContext,
  heap : CHeap,
  environment : PreparedGCEnvironment,
) -> Unit raise GCSetupError {
  if c_jit_context_is_valid(self.handle) == 0 {
    raise MissingJITContext
  }
  guard physical_equal(self.handle, environment.context) else {
    raise InvalidMetadata
  }
  gc_set_heap(self.handle, heap)
  self.handle.bind_gc_metadata(
    environment.types,
    environment.canonical,
    environment.functions,
  ) catch {
    _ => raise InvalidMetadata
  }
  self.handle.bind_gc_function_addresses(environment.addresses)
}
