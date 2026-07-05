///|
/// JIT runtime FFI for executable memory management and code execution
/// Uses @jit_ffi package for C function declarations

// ============ Trap Handling ============

///|
/// Error for JIT trap
pub suberror JITTrap {
  JITTrap(String)
  JITExit(Int)
} derive(Debug)

///|
/// Keep `Show` behavior while migrating from deprecated `derive(Show)` to
/// `derive(Debug)`.
pub impl Show for JITTrap with fn output(self, logger) {
  logger.write_string(@types.compact_show_repr(to_repr(self).to_string()))
}

// ============ JIT Context Wrapper ============

///|
/// JIT execution context (JIT ABI) - GC managed
/// TODO(wasmoon_jit): move entry trampoline generation to
/// `wasmoon_jit.plan_entry_trampoline_for_target` after the reusable
/// trampoline passes the full WAST/testsuite production gate, then move this
/// context into `wasmoon_jit`.
/// Uses Standard on-demand loading from vmctx:
/// +0: memory0 descriptor, +8: memory0_base, +16: memory0_size,
/// +24: func_table, +32: table0_base.
/// Only pinned vmctx is cached; all other values are loaded on-demand.
/// Memory is automatically freed when the object is garbage collected
priv struct JITContext {
  ctx : @wasmoon_jit.NativeJITContext
  // Trampoline cache: maps signature hash to generated trampoline
  // Signature hash = hash of (param_types, result_types)
  trampoline_cache : Map[Int64, @wasmoon_jit.ExecCode]
}

///|
/// Create a new JIT context - GC managed
fn JITContext::new(total_funcs : Int) -> JITContext? {
  @wasmoon_jit.NativeJITContext::new(total_funcs).map(fn(ctx) {
    { ctx, trampoline_cache: Map([]) }
  })
}

///|
/// Get the raw context pointer (for FFI calls)
fn JITContext::ptr(self : JITContext) -> Int64 {
  self.ctx.ptr()
}

///|
/// Set a function pointer in the context
fn JITContext::set_func(self : JITContext, idx : Int, func_ptr : Int64) -> Unit {
  self.ctx.set_func(idx, func_ptr)
}

///|
/// Allocate indirect table for call_indirect
fn JITContext::alloc_indirect_table(self : JITContext, count : Int) -> Bool {
  self.ctx.alloc_indirect_table(count)
}

///|
/// Set an entry in indirect table (maps table_idx to func_idx with type_idx for type checking)
fn JITContext::set_indirect(
  self : JITContext,
  table_idx : Int,
  func_idx : Int,
  type_idx : Int,
) -> Unit {
  self.ctx.set_indirect(table_idx, func_idx, type_idx)
}

///|
/// Set memory0 in the context
fn JITContext::set_memory(self : JITContext, mem0_ptr : Int64) -> Unit {
  self.ctx.set_memory(mem0_ptr)
}

///|
/// Set globals array in the context
fn JITContext::set_globals(self : JITContext, globals_ptr : Int64) -> Unit {
  self.ctx.set_globals(globals_ptr)
}

///|
/// Allocate guarded memory with mmap for bounds check elimination
/// Memory is allocated with guard pages (PROT_NONE) after the accessible region
/// Access to guard pages triggers SIGSEGV which is caught and converted to a trap
/// Returns: memory pointer on success, 0 on failure
fn JITContext::alloc_guarded_memory(
  self : JITContext,
  initial_pages : Int,
  max_pages : Int?,
) -> Int64 {
  self.ctx.alloc_guarded_memory(initial_pages, max_pages)
}

///|
/// Get the function table base pointer
fn JITContext::get_func_table_ptr(self : JITContext) -> Int64 {
  self.ctx.func_table_ptr()
}

///|
/// Set multiple indirect tables (for multi-table support)
/// jit_tables: Array of JITTable? from Store
/// This enables proper multi-table support where each call_indirect can specify which table to use
fn JITContext::set_table_pointers(
  self : JITContext,
  jit_tables : Array[@wasmoon_jit.JITTable?],
) -> Unit {
  self.ctx.set_table_pointers(jit_tables)
}

///|
/// Set multiple memories (for multi-memory support)
fn JITContext::set_memory_pointers(
  self : JITContext,
  memories : Array[@wasmoon_jit.MemoryInfo],
) -> Unit {
  self.ctx.set_memory_pointers(memories)
}

///|
fn JITContext::get_memory_ptr(self : JITContext, memidx : Int) -> Int64 {
  self.ctx.memory_ptr(memidx)
}

///|
fn JITContext::get_memory_size(self : JITContext, memidx : Int) -> Int64 {
  self.ctx.memory_size(memidx)
}

///|
/// Allocate an independent WASM stack with guard page protection.
/// This provides controlled stack overflow behavior - when WASM code
/// overflows the stack, it hits the guard page and triggers a
/// "call stack exhausted" trap instead of crashing.
///
/// Parameters:
///   stack_size: Size of the stack in bytes (default: 1MB = 1048576)
///
/// Returns: true on success, false on failure
fn JITContext::alloc_wasm_stack(self : JITContext, stack_size : Int64) -> Bool {
  self.ctx.alloc_wasm_stack(stack_size)
}

///|
/// Check if a WASM stack has been allocated
fn JITContext::has_wasm_stack(self : JITContext) -> Bool {
  self.ctx.has_wasm_stack()
}

// ============ WASI Initialization ============

///|
/// Initialize WASI context with args, env, and preopens
fn JITContext::init_wasi(
  self : JITContext,
  args : Array[String],
  env : Array[String],
  preopens : Array[(String, String)],
) -> Unit {
  @wasmoon_jit.init_wasi_context(self.ptr(), args, env, preopens)
}

///|
/// Initialize WASI context with stdout/stderr redirected to /dev/null (for testing)
fn JITContext::init_wasi_quiet(
  self : JITContext,
  args : Array[String],
  env : Array[String],
  preopens : Array[(String, String)],
) -> Unit {
  @wasmoon_jit.init_wasi_context(self.ptr(), args, env, preopens, quiet=true)
}

///|
/// Enable or disable WASI stdout capture
fn JITContext::set_wasi_stdout_capture(
  self : JITContext,
  enabled : Bool,
) -> Unit {
  @wasmoon_jit.set_wasi_stdout_capture(self.ptr(), enabled)
}

///|
/// Enable or disable WASI stderr capture
fn JITContext::set_wasi_stderr_capture(
  self : JITContext,
  enabled : Bool,
) -> Unit {
  @wasmoon_jit.set_wasi_stderr_capture(self.ptr(), enabled)
}

///|
/// Set WASI stdin buffer (custom stdin)
fn JITContext::set_wasi_stdin_buffer(self : JITContext, data : Bytes) -> Unit {
  @wasmoon_jit.set_wasi_stdin_buffer(self.ptr(), data)
}

///|
/// Set WASI stdin callback (custom stdin)
fn JITContext::set_wasi_stdin_callback(
  self : JITContext,
  callback : () -> Bytes,
) -> Unit {
  @wasmoon_jit.set_wasi_stdin_callback(self.ptr(), callback)
}

///|
/// Set hostcall callback for JIT -> host bridging.
/// The callback is invoked with no arguments and should return 0 on success,
/// or a trap code on failure.
fn JITContext::set_hostcall_callback(
  self : JITContext,
  callback : () -> Int,
) -> Unit {
  self.ctx.set_hostcall_callback(callback)
}

///|
fn JITContext::clear_hostcall_callback(self : JITContext) -> Unit {
  self.ctx.clear_hostcall_callback()
}

///|
/// Clear WASI stdin callback
fn JITContext::clear_wasi_stdin_callback(self : JITContext) -> Unit {
  @wasmoon_jit.clear_wasi_stdin_callback(self.ptr())
}

///|
/// Clear WASI stdin buffer
fn JITContext::clear_wasi_stdin_buffer(self : JITContext) -> Unit {
  @wasmoon_jit.clear_wasi_stdin_buffer(self.ptr())
}

///|
/// Take captured stdout bytes (and clear buffer)
fn JITContext::take_wasi_stdout(self : JITContext) -> Bytes {
  @wasmoon_jit.take_wasi_stdout(self.ptr())
}

///|
/// Take captured stderr bytes (and clear buffer)
fn JITContext::take_wasi_stderr(self : JITContext) -> Bytes {
  @wasmoon_jit.take_wasi_stderr(self.ptr())
}

// ============ Multi-value Return Support ============

///|
/// Call a JIT function with multiple return values
/// Uses JIT-generated trampolines on-demand.
/// X19 = ctx_ptr (vmctx), all other values loaded on-demand from vmctx.
/// Returns 0 on success, trap code on error
fn JITContext::call_multi_return(
  self : JITContext,
  func_ptr : Int64,
  args : Array[Int64],
  param_types : Array[@types.ValueType],
  results : Array[Int64],
  result_types : Array[@types.ValueType],
) -> Unit raise JITTrap {
  let num_arg_slots = args.length() // Number of Int64 slots (V128 takes 2)
  let num_params = param_types.length()
  let num_result_slots = @wasmoon_jit.count_entry_trampoline_slots(result_types)
  let sig_hash = @wasmoon_jit.entry_trampoline_signature_hash(
    param_types, result_types,
  )

  // Get or generate trampoline
  let trampoline_ptr = match self.trampoline_cache.get(sig_hash) {
    Some(trampoline) => trampoline.ptr()
    None => {
      let param_codes_arr : Array[Int] = []
      for i in 0..<num_params {
        param_codes_arr.push(
          @wasmoon_jit.entry_trampoline_value_type_code(param_types[i]),
        )
      }
      let result_codes_arr : Array[Int] = []
      for result_type in result_types {
        result_codes_arr.push(
          @wasmoon_jit.entry_trampoline_value_type_code(result_type),
        )
      }
      let mc = @emit.emit_entry_trampoline(param_codes_arr, result_codes_arr)
      let code_ints = mc.get_bytes()
      let trampoline = @wasmoon_jit.ExecCode::new(code_ints)
      match trampoline {
        Some(t) => {
          let ptr = t.ptr()
          self.trampoline_cache.set(sig_hash, t)
          ptr
        }
        None => abort("Failed to allocate trampoline")
      }
    }
  }

  // Prepare values_vec: [args..., results...]
  // Each slot is 8 bytes (Int64), V128 uses 2 slots
  let values_len = num_arg_slots + num_result_slots
  let values_vec = FixedArray::make(values_len.max(1), 0L)

  // Copy args to values_vec
  for i in 0..<num_arg_slots {
    values_vec[i] = args[i]
  }

  // Call via trampoline (Standard: all ABI complexity in JIT code)
  // Use stack-switching call if a WASM stack has been allocated
  let trap_code = self.ctx.call_trampoline(
    trampoline_ptr,
    func_ptr,
    values_vec,
    values_len,
    self.has_wasm_stack(),
  )
  if trap_code != 0 {
    if @wasmoon_jit.is_wasi_exit_trap_code(trap_code) {
      raise JITExit(@wasmoon_jit.take_wasi_exit_code(self.ptr()))
    }
    raise JITTrap(@wasmoon_jit.jit_trap_message(trap_code))
  }

  // Copy results back from values_vec (results start after args)
  // V128 results take 2 slots
  for i in 0..<num_result_slots {
    results[i] = values_vec[num_arg_slots + i]
  }
}
