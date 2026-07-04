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
/// TODO(ISS-022): move entry trampoline generation to
/// `wasmoon_jit.plan_entry_trampoline_for_target` after the reusable
/// trampoline passes the full WAST/testsuite production gate, then move this
/// context into `wasmoon_jit`.
/// Uses Standard on-demand loading from vmctx:
/// +0: memory0 descriptor, +8: memory0_base, +16: memory0_size,
/// +24: func_table, +32: table0_base.
/// Only pinned vmctx is cached; all other values are loaded on-demand.
/// Memory is automatically freed when the object is garbage collected
priv struct JITContext {
  ctx : @jit_ffi.JITContext
  // Trampoline cache: maps signature hash to generated trampoline
  // Signature hash = hash of (param_types, result_types)
  trampoline_cache : Map[Int64, @wasmoon_jit.ExecCode]
}

///|
/// Create a new JIT context - GC managed
fn JITContext::new(total_funcs : Int) -> JITContext? {
  let ctx = @jit_ffi.c_jit_alloc_context_managed(total_funcs)
  let ctx_ptr = @jit_ffi.c_jit_context_ptr(ctx)
  // Check if allocation succeeded by verifying the pointer is valid
  if ctx_ptr != 0L {
    Some({ ctx, trampoline_cache: Map([]) })
  } else {
    None
  }
}

///|
/// Get the raw context pointer (for FFI calls)
fn JITContext::ptr(self : JITContext) -> Int64 {
  @jit_ffi.c_jit_context_ptr(self.ctx)
}

///|
/// Set a function pointer in the context
fn JITContext::set_func(self : JITContext, idx : Int, func_ptr : Int64) -> Unit {
  @jit_ffi.c_jit_ctx_set_func(self.ptr(), idx, func_ptr)
}

///|
/// Allocate indirect table for call_indirect
fn JITContext::alloc_indirect_table(self : JITContext, count : Int) -> Bool {
  @jit_ffi.c_jit_ctx_alloc_indirect_table(self.ptr(), count) != 0
}

///|
/// Set an entry in indirect table (maps table_idx to func_idx with type_idx for type checking)
fn JITContext::set_indirect(
  self : JITContext,
  table_idx : Int,
  func_idx : Int,
  type_idx : Int,
) -> Unit {
  @jit_ffi.c_jit_ctx_set_indirect(self.ptr(), table_idx, func_idx, type_idx)
}

///|
/// Set memory0 in the context
fn JITContext::set_memory(self : JITContext, mem0_ptr : Int64) -> Unit {
  @jit_ffi.c_jit_ctx_set_memory(self.ptr(), mem0_ptr)
}

///|
/// Set globals array in the context
fn JITContext::set_globals(self : JITContext, globals_ptr : Int64) -> Unit {
  @jit_ffi.c_jit_ctx_set_globals(self.ptr(), globals_ptr)
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
  let max_pages_val = max_pages.unwrap_or(-1).to_int64()
  @jit_ffi.c_jit_ctx_alloc_guarded_memory(
    self.ptr(),
    initial_pages.to_int64(),
    max_pages_val,
  )
}

///|
/// Get the function table base pointer
fn JITContext::get_func_table_ptr(self : JITContext) -> Int64 {
  @jit_ffi.c_jit_ctx_get_func_table(self.ptr())
}

///|
/// Set multiple indirect tables (for multi-table support)
/// jit_tables: Array of JITTable? from Store
/// This enables proper multi-table support where each call_indirect can specify which table to use
fn JITContext::set_table_pointers(
  self : JITContext,
  jit_tables : Array[@wasmoon_jit.JITTable?],
) -> Unit {
  if jit_tables.is_empty() {
    return
  }
  // Convert Array[JITTable?] to FixedArray[Int64] of table pointers, sizes, and max sizes
  let table_ptrs = FixedArray::make(jit_tables.length(), 0L)
  let table_sizes = FixedArray::make(jit_tables.length(), 0)
  let table_max_sizes = FixedArray::make(jit_tables.length(), -1) // -1 = unlimited
  for i, jit_table_opt in jit_tables {
    match jit_table_opt {
      Some(jit_table) => {
        table_ptrs[i] = jit_table.raw_ptr()
        table_sizes[i] = jit_table.get_size()
        table_max_sizes[i] = jit_table.get_max().unwrap_or(-1)
      }
      None => {
        table_ptrs[i] = 0L // Null table pointer
        table_sizes[i] = 0
        table_max_sizes[i] = -1
      }
    }
  }
  @jit_ffi.c_jit_ctx_set_table_pointers(
    self.ptr(),
    table_ptrs,
    table_sizes,
    table_max_sizes,
    jit_tables.length(),
  )
}

///|
/// Set multiple memories (for multi-memory support)
fn JITContext::set_memory_pointers(
  self : JITContext,
  memories : Array[@wasmoon_jit.MemoryInfo],
) -> Unit {
  if memories.is_empty() {
    return
  }
  let count = memories.length()
  // Convert to FixedArray for FFI
  let ptrs = FixedArray::make(count, 0L)
  for i, mem in memories {
    ptrs[i] = mem.ptr
  }
  @jit_ffi.c_jit_ctx_set_memory_pointers(self.ptr(), ptrs, count)
}

///|
fn JITContext::get_memory_ptr(self : JITContext, memidx : Int) -> Int64 {
  @jit_ffi.c_jit_ctx_get_memory_ptr(self.ptr(), memidx)
}

///|
fn JITContext::get_memory_size(self : JITContext, memidx : Int) -> Int64 {
  @jit_ffi.c_jit_ctx_get_memory_size(self.ptr(), memidx)
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
  @jit_ffi.c_jit_alloc_wasm_stack(self.ptr(), stack_size) == 0
}

///|
/// Check if a WASM stack has been allocated
fn JITContext::has_wasm_stack(self : JITContext) -> Bool {
  @jit_ffi.c_jit_get_wasm_stack_top(self.ptr()) != 0L
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
  let call_closure : FuncRef[(() -> Int) -> Int] = fn(f : () -> Int) { f() }
  @jit_ffi.c_jit_set_hostcall_callback(self.ptr(), call_closure, callback)
}

///|
fn JITContext::clear_hostcall_callback(self : JITContext) -> Unit {
  @jit_ffi.c_jit_clear_hostcall_callback(self.ptr())
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
  let use_reusable_trampoline = @wasmoon_jit.can_use_reusable_entry_trampoline(
    param_types, result_types,
  )
  let num_result_slots = @wasmoon_jit.count_entry_trampoline_slots(result_types)
  let sig_hash = @wasmoon_jit.entry_trampoline_signature_hash(
    param_types, result_types,
  )

  // Get or generate trampoline
  let trampoline_ptr = match self.trampoline_cache.get(sig_hash) {
    Some(trampoline) => trampoline.ptr()
    None => {
      let code_ints = if use_reusable_trampoline {
        let target : @machv_emit.EmitTarget = match @isa.ISA::current() {
          AArch64 => AArch64
          AMD64 => X64
        }
        @wasmoon_jit.plan_entry_trampoline_for_target(
          param_types, result_types, target,
        ).object.code catch {
          err => raise JITTrap(to_repr(err).to_string())
        }
      } else {
        // TODO(ISS-022): remove this legacy fallback after the reusable entry
        // trampoline models production ABI surfaces beyond the currently proven
        // scalar register-only slice: stack-passed entry params, overflow Wasm
        // call args/results, reference-root handling, FP packing, and V128 lane
        // extract/insert operations.
        let param_codes_arr = @wasmoon_jit.entry_trampoline_type_codes(
          param_types,
        )
        let result_codes_arr = @wasmoon_jit.entry_trampoline_type_codes(
          result_types,
        )
        @emit.emit_entry_trampoline(param_codes_arr, result_codes_arr).get_bytes()
      }
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
  let trap_code = if self.has_wasm_stack() {
    @jit_ffi.c_jit_call_with_stack_switch_managed(
      self.ctx,
      trampoline_ptr,
      func_ptr,
      values_vec,
      values_len,
    )
  } else {
    @jit_ffi.c_jit_call_trampoline_managed(
      self.ctx,
      trampoline_ptr,
      func_ptr,
      values_vec,
      values_len,
    )
  }
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
