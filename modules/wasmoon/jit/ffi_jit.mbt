///|
/// JIT runtime FFI for executable memory management and code execution
/// Uses the Wasmoon-owned JIT facade for native runtime operations.

// ============ Trap Handling ============

///|
/// Terminal failure reported by a JIT invocation.
pub suberror JITTrap {
  JITTrap(String)
  JITNativeFiberFailure(String)
  JITExit(Int)
  JITCancelled
} derive(Debug)

///|
/// Keep `Show` behavior while migrating from deprecated `derive(Show)` to
/// `derive(Debug)`.
pub impl Show for JITTrap with fn output(self, logger) {
  logger.write_string(@types.compact_show_repr(Repr(self).to_string()))
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
  trampoline_cache : Map[Int64, @wasmoon_jit.InstalledTrampoline]
}

///|
/// Create a new JIT context - GC managed
fn JITContext::try_alloc(total_funcs : Int) -> JITContext? {
  @wasmoon_jit.NativeJITContext::try_alloc(total_funcs).map(fn(ctx) {
    { ctx, trampoline_cache: Map([]), }
  })
}

///|
fn JITContext::close(self : JITContext) -> Unit {
  self.clear_hostcall_callback()
  self.clear_cancellation_callback()
  self.clear_wasi_stdin_callback()
  self.clear_wasi_stdin_buffer()
  for entry in self.trampoline_cache {
    entry.1.release()
  }
  self.trampoline_cache.clear()
}

///|
/// Set a function pointer in the context
fn JITContext::set_func(self : JITContext, idx : Int, func_ptr : Int64) -> Unit {
  self.ctx.set_func(idx, func_ptr)
}

///|
fn JITContext::register_safepoints(
  self : JITContext,
  func_idx : Int,
  safepoints : Array[@code_object.SafepointSite],
) -> Bool {
  self.ctx.register_safepoints(func_idx, safepoints)
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
fn JITContext::refresh_table_layout(self : JITContext, table_idx : Int) -> Bool {
  self.ctx.refresh_table_layout(table_idx)
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
/// Configure the guarded native-fiber stack used by JIT calls.
/// Allocation is deferred until a native continuation starts.
///
/// Parameters:
///   stack_size: Size of the stack in bytes (default: 1MB = 1048576)
///
/// Returns: true when the configuration was accepted.
fn JITContext::configure_native_fiber_stack_size(
  self : JITContext,
  stack_size : Int64,
) -> Bool {
  self.ctx.configure_native_fiber_stack_size(stack_size)
}

///|
/// Check if a native-fiber stack size has been configured.
fn JITContext::has_configured_native_fiber_stack_size(
  self : JITContext,
) -> Bool {
  self.ctx.has_configured_native_fiber_stack_size()
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
  self.ctx.init_wasi(args, env, preopens)
}

///|
/// Initialize WASI context with stdout/stderr redirected to /dev/null (for testing)
fn JITContext::init_wasi_quiet(
  self : JITContext,
  args : Array[String],
  env : Array[String],
  preopens : Array[(String, String)],
) -> Unit {
  self.ctx.init_wasi(args, env, preopens, quiet=true)
}

///|
/// Enable or disable WASI stdout capture
fn JITContext::set_wasi_stdout_capture(
  self : JITContext,
  enabled : Bool,
) -> Unit {
  self.ctx.set_wasi_stdout_capture(enabled)
}

///|
/// Enable or disable WASI stderr capture
fn JITContext::set_wasi_stderr_capture(
  self : JITContext,
  enabled : Bool,
) -> Unit {
  self.ctx.set_wasi_stderr_capture(enabled)
}

///|
/// Set WASI stdin buffer (custom stdin)
fn JITContext::set_wasi_stdin_buffer(self : JITContext, data : Bytes) -> Unit {
  self.ctx.set_wasi_stdin_buffer(data)
}

///|
/// Set WASI stdin callback (custom stdin)
fn JITContext::set_wasi_stdin_callback(
  self : JITContext,
  callback : () -> Bytes,
) -> Unit {
  self.ctx.set_wasi_stdin_callback(callback)
}

///|
/// Set hostcall callback for JIT -> host bridging.
fn JITContext::set_hostcall_callback(
  self : JITContext,
  callback : () -> @wasmoon_jit.NativeHostcallOutcome,
) -> Unit {
  self.ctx.set_hostcall_callback(callback)
}

///|
fn JITContext::clear_hostcall_callback(self : JITContext) -> Unit {
  self.ctx.clear_hostcall_callback()
}

///|
fn JITContext::set_cancellation_callback(
  self : JITContext,
  callback : () -> Bool,
) -> Unit {
  self.ctx.set_cancellation_callback(callback)
}

///|
fn JITContext::clear_cancellation_callback(self : JITContext) -> Unit {
  self.ctx.clear_cancellation_callback()
}

///|
/// Clear WASI stdin callback
fn JITContext::clear_wasi_stdin_callback(self : JITContext) -> Unit {
  self.ctx.clear_wasi_stdin_callback()
}

///|
/// Clear WASI stdin buffer
fn JITContext::clear_wasi_stdin_buffer(self : JITContext) -> Unit {
  self.ctx.clear_wasi_stdin_buffer()
}

///|
/// Take captured stdout bytes (and clear buffer)
fn JITContext::take_wasi_stdout(self : JITContext) -> Bytes {
  self.ctx.take_wasi_stdout()
}

///|
/// Take captured stderr bytes (and clear buffer)
fn JITContext::take_wasi_stderr(self : JITContext) -> Bytes {
  self.ctx.take_wasi_stderr()
}

// ============ Multi-value Return Support ============

///|
fn JITContext::entry_trampoline(
  self : JITContext,
  param_types : Array[@types.ValueType],
  result_types : Array[@types.ValueType],
) -> Int64 raise JITTrap {
  let sig_hash = @wasmoon_jit.entry_trampoline_signature_hash(
    param_types, result_types,
  )
  match self.trampoline_cache.get(sig_hash) {
    Some(trampoline) => trampoline.entry_address()
    None => {
      let target_arch = @wasmoon_jit.host_native_target() catch {
        err => raise JITTrap("unsupported host target: \{err}")
      }
      let code_ints = @wasmoon_jit.build_entry_trampoline_for_target(
        param_types, result_types, target_arch,
      ) catch {
        err => raise JITTrap("entry trampoline generation failed: \{err}")
      }
      let installer = @wasmoon_jit.JitCodeInstaller::new(fn(_) { None })
      let trampoline = installer.install_trampoline(code_ints) catch {
        err =>
          raise JITTrap("entry trampoline installation failed: \{Repr(err)}")
      }
      let pointer = trampoline.entry_address()
      self.trampoline_cache.set(sig_hash, trampoline)
      pointer
    }
  }
}

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
  let num_result_slots = @wasmoon_jit.count_entry_trampoline_slots(result_types)
  let trampoline_ptr = self.entry_trampoline(param_types, result_types)

  // Prepare values_vec: [args..., results...]
  // Each slot is 8 bytes (Int64), V128 uses 2 slots
  let values_len = num_arg_slots + num_result_slots
  let values_vec = FixedArray::make(values_len.max(1), 0L)

  // Copy args to values_vec
  for i in 0..<num_arg_slots {
    values_vec[i] = args[i]
  }

  // Call via trampoline (Standard: all ABI complexity in JIT code)
  // All production JIT calls use the native-fiber trap transport. The
  // configured stack size overrides its default budget when present.
  let trap_code = self.ctx.call_trampoline(
    trampoline_ptr, func_ptr, values_vec, values_len, true,
  ) catch {
    error => raise JITNativeFiberFailure(error.to_string())
  }
  if trap_code != 0 {
    if @wasmoon_jit.is_wasi_exit_trap_code(trap_code) {
      raise JITExit(self.ctx.take_wasi_exit_code())
    }
    if @wasmoon_jit.is_cancelled_trap_code(trap_code) {
      raise JITCancelled
    }
    raise JITTrap(@wasmoon_jit.jit_trap_message(trap_code))
  }

  // Copy results back from values_vec (results start after args)
  // V128 results take 2 slots
  for i in 0..<num_result_slots {
    results[i] = values_vec[num_arg_slots + i]
  }
}

///|
priv struct JITContextContinuation {
  raw : @wasmoon_jit.NativeJITContinuation
  context : @wasmoon_jit.NativeJITContext
  values : FixedArray[Int64]
  num_arg_slots : Int
  num_result_slots : Int
  active : Array[Bool]
}

///|
priv enum JITContextContinuationEvent {
  Suspended
  Returned(Array[Int64])
}

///|
fn JITContext::start_continuation(
  self : JITContext,
  func_ptr : Int64,
  args : Array[Int64],
  param_types : Array[@types.ValueType],
  result_types : Array[@types.ValueType],
) -> JITContextContinuation raise JITTrap {
  let num_arg_slots = args.length()
  let num_result_slots = @wasmoon_jit.count_entry_trampoline_slots(result_types)
  let values_len = num_arg_slots + num_result_slots
  let values = FixedArray::make(values_len.max(1), 0L)
  for i in 0..<num_arg_slots {
    values[i] = args[i]
  }
  let raw = self.ctx.start_continuation(
    self.entry_trampoline(param_types, result_types),
    func_ptr,
    values,
    values_len,
  ) catch {
    error => raise JITNativeFiberFailure(error.to_string())
  }
  {
    raw,
    context: self.ctx,
    values,
    num_arg_slots,
    num_result_slots,
    active: [true],
  }
}

///|
fn JITContextContinuation::advance(
  self : JITContextContinuation,
  retry_hostcall : Bool,
) -> JITContextContinuationEvent raise JITTrap {
  if !self.active[0] {
    raise JITTrap("native continuation is no longer active")
  }
  let event = self.raw.continue_after_hostcall(retry=retry_hostcall) catch {
    error => {
      self.active[0] = false
      raise JITNativeFiberFailure(error.to_string())
    }
  }
  match event {
    NativeHostcallSuspended => Suspended
    NativeJITTrapped(trap_code) => {
      self.active[0] = false
      if @wasmoon_jit.is_wasi_exit_trap_code(trap_code) {
        raise JITExit(self.context.take_wasi_exit_code())
      }
      if @wasmoon_jit.is_cancelled_trap_code(trap_code) {
        raise JITCancelled
      }
      raise JITTrap(@wasmoon_jit.jit_trap_message(trap_code))
    }
    NativeJITCompleted => {
      self.active[0] = false
      let results : Array[Int64] = []
      for i in 0..<self.num_result_slots {
        results.push(self.values[self.num_arg_slots + i])
      }
      Returned(results)
    }
  }
}

///|
fn JITContextContinuation::cancel(
  self : JITContextContinuation,
) -> Unit raise JITTrap {
  if !self.active[0] {
    return
  }
  self.raw.cancel() catch {
    error => raise JITNativeFiberFailure(error.to_string())
  }
  self.active[0] = false
}
