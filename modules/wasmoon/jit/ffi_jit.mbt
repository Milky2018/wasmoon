///|
/// JIT runtime FFI for executable memory management and code execution
/// Uses @jit_ffi package for C function declarations

///|
pub using @jit_ffi {c_jit_write_i64, c_jit_write_u32, c_jit_read_i64}

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

///|
/// Get the last captured trap details (best-effort).
/// These fields are reset at the start of each JIT call.
pub fn get_last_trap_details() -> @wasmoon_jit.TrapDetails {
  @wasmoon_jit.get_last_trap_details()
}

///|
/// Check if trap occurred and raise error if so
/// Trap codes (matching WebAssembly trap types):
/// 1 = out of bounds memory access
/// 2 = call stack exhausted
/// 3 = unreachable executed
/// 4 = indirect call type mismatch
/// 5 = invalid conversion to integer
/// 6 = integer divide by zero
/// 7 = integer overflow
/// 8 = backend/unknown JIT trap site
/// 9 = out of memory
/// 10 = gc precise roots unavailable
/// 99 = unknown trap
pub fn check_trap() -> Unit raise JITTrap {
  match @wasmoon_jit.take_pending_trap_message() {
    Some(msg) => raise JITTrap(msg)
    None => ()
  }
}

// ============ Hostcall Dispatch Info ============

///|
/// Get the runtime store function address for the current JIT -> hostcall.
///
/// This value is set by `wasmoon_jit_hostcall` right before invoking the
/// MoonBit hostcall callback.
pub fn get_hostcall_func_addr() -> Int {
  @wasmoon_jit.get_hostcall_func_addr()
}

///|
/// Get the pointer to the hostcall scratch `values_vec` buffer.
pub fn get_hostcall_values_ptr() -> Int64 {
  @wasmoon_jit.get_hostcall_values_ptr()
}

///|
/// Get the number of argument *slots* in `values_vec`.
///
/// Note: slots are 8 bytes each; V128 occupies 2 slots.
pub fn get_hostcall_num_arg_slots() -> Int {
  @wasmoon_jit.get_hostcall_num_arg_slots()
}

///|
/// Get the number of result *slots* in `values_vec`.
///
/// Note: slots are 8 bytes each; V128 occupies 2 slots.
pub fn get_hostcall_num_result_slots() -> Int {
  @wasmoon_jit.get_hostcall_num_result_slots()
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
/// Convert String to null-terminated FixedArray[Byte] for C FFI (UTF-8 encoding)
fn string_to_cstring(s : String) -> FixedArray[Byte] {
  let len = s.length()
  // First pass: calculate required size
  let mut size = 0
  let mut i = 0
  while i < len {
    let c = s.code_unit_at(i).to_int()
    if c < 0x80 {
      size += 1
      i += 1
    } else if c < 0x800 {
      size += 2
      i += 1
    } else if c >= 0xD800 && c <= 0xDBFF && i + 1 < len {
      let c2 = s.code_unit_at(i + 1).to_int()
      if c2 >= 0xDC00 && c2 <= 0xDFFF {
        size += 4
        i += 2
      } else {
        size += 3
        i += 1
      }
    } else {
      size += 3
      i += 1
    }
  }
  // Allocate with null terminator
  let result = FixedArray::make(size + 1, b'\x00')
  // Second pass: encode UTF-8
  let mut pos = 0
  i = 0
  while i < len {
    let c = s.code_unit_at(i).to_int()
    if c < 0x80 {
      result[pos] = c.to_byte()
      pos += 1
      i += 1
    } else if c < 0x800 {
      result[pos] = (0xC0 | (c >> 6)).to_byte()
      result[pos + 1] = (0x80 | (c & 0x3F)).to_byte()
      pos += 2
      i += 1
    } else if c >= 0xD800 && c <= 0xDBFF && i + 1 < len {
      let c2 = s.code_unit_at(i + 1).to_int()
      if c2 >= 0xDC00 && c2 <= 0xDFFF {
        let codepoint = 0x10000 + ((c - 0xD800) << 10) + (c2 - 0xDC00)
        result[pos] = (0xF0 | (codepoint >> 18)).to_byte()
        result[pos + 1] = (0x80 | ((codepoint >> 12) & 0x3F)).to_byte()
        result[pos + 2] = (0x80 | ((codepoint >> 6) & 0x3F)).to_byte()
        result[pos + 3] = (0x80 | (codepoint & 0x3F)).to_byte()
        pos += 4
        i += 2
      } else {
        // Invalid surrogate, encode as replacement character.
        result[pos] = b'\xEF'
        result[pos + 1] = b'\xBF'
        result[pos + 2] = b'\xBD'
        pos += 3
        i += 1
      }
    } else {
      result[pos] = (0xE0 | (c >> 12)).to_byte()
      result[pos + 1] = (0x80 | ((c >> 6) & 0x3F)).to_byte()
      result[pos + 2] = (0x80 | (c & 0x3F)).to_byte()
      pos += 3
      i += 1
    }
  }
  result[size] = b'\x00'
  result
}

///|
/// Initialize WASI context with args, env, and preopens
fn JITContext::init_wasi(
  self : JITContext,
  args : Array[String],
  env : Array[String],
  preopens : Array[(String, String)],
) -> Unit {
  let ctx_ptr = self.ptr()
  // Initialize fd table
  @jit_ffi.c_jit_init_wasi_fds(ctx_ptr, preopens.length())
  // Reset stdio capture/buffers
  self.set_wasi_stdout_capture(false)
  self.set_wasi_stderr_capture(false)
  self.clear_wasi_stdin_callback()
  self.clear_wasi_stdin_buffer()
  // Set args
  @jit_ffi.c_jit_set_wasi_args(ctx_ptr, args.length())
  for i, arg in args {
    let cstr = string_to_cstring(arg)
    @jit_ffi.c_jit_set_wasi_arg(ctx_ptr, i, cstr)
  }
  // Set env
  @jit_ffi.c_jit_set_wasi_envs(ctx_ptr, env.length())
  for i, e in env {
    let cstr = string_to_cstring(e)
    @jit_ffi.c_jit_set_wasi_env(ctx_ptr, i, cstr)
  }
  // Set preopens
  for i, entry in preopens {
    let (host, guest) = entry
    let host_cstr = string_to_cstring(host)
    let guest_cstr = string_to_cstring(guest)
    @jit_ffi.c_jit_add_preopen(ctx_ptr, i, host_cstr, guest_cstr)
  }
}

///|
/// Initialize WASI context with stdout/stderr redirected to /dev/null (for testing)
fn JITContext::init_wasi_quiet(
  self : JITContext,
  args : Array[String],
  env : Array[String],
  preopens : Array[(String, String)],
) -> Unit {
  let ctx_ptr = self.ptr()
  // Initialize fd table with quiet mode (stdout/stderr to /dev/null)
  @jit_ffi.c_jit_init_wasi_fds_quiet(ctx_ptr, preopens.length())
  // Reset stdio capture/buffers
  self.set_wasi_stdout_capture(false)
  self.set_wasi_stderr_capture(false)
  self.clear_wasi_stdin_callback()
  self.clear_wasi_stdin_buffer()
  // Set args
  @jit_ffi.c_jit_set_wasi_args(ctx_ptr, args.length())
  for i, arg in args {
    let cstr = string_to_cstring(arg)
    @jit_ffi.c_jit_set_wasi_arg(ctx_ptr, i, cstr)
  }
  // Set env
  @jit_ffi.c_jit_set_wasi_envs(ctx_ptr, env.length())
  for i, e in env {
    let cstr = string_to_cstring(e)
    @jit_ffi.c_jit_set_wasi_env(ctx_ptr, i, cstr)
  }
  // Set preopens
  for i, entry in preopens {
    let (host, guest) = entry
    let host_cstr = string_to_cstring(host)
    let guest_cstr = string_to_cstring(guest)
    @jit_ffi.c_jit_add_preopen(ctx_ptr, i, host_cstr, guest_cstr)
  }
}

///|
/// Enable or disable WASI stdout capture
fn JITContext::set_wasi_stdout_capture(
  self : JITContext,
  enabled : Bool,
) -> Unit {
  let value = if enabled { 1 } else { 0 }
  @jit_ffi.c_jit_set_wasi_stdout_capture(self.ptr(), value)
}

///|
/// Enable or disable WASI stderr capture
fn JITContext::set_wasi_stderr_capture(
  self : JITContext,
  enabled : Bool,
) -> Unit {
  let value = if enabled { 1 } else { 0 }
  @jit_ffi.c_jit_set_wasi_stderr_capture(self.ptr(), value)
}

///|
/// Set WASI stdin buffer (custom stdin)
fn JITContext::set_wasi_stdin_buffer(self : JITContext, data : Bytes) -> Unit {
  @jit_ffi.c_jit_set_wasi_stdin_buffer(self.ptr(), data, data.length())
}

///|
/// Set WASI stdin callback (custom stdin)
fn JITContext::set_wasi_stdin_callback(
  self : JITContext,
  callback : () -> Bytes,
) -> Unit {
  let call_closure : FuncRef[(() -> Bytes) -> Bytes] = fn(f : () -> Bytes) {
    f()
  }
  @jit_ffi.c_jit_set_wasi_stdin_callback(self.ptr(), call_closure, callback)
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
  @jit_ffi.c_jit_clear_wasi_stdin_callback(self.ptr())
}

///|
/// Clear WASI stdin buffer
fn JITContext::clear_wasi_stdin_buffer(self : JITContext) -> Unit {
  @jit_ffi.c_jit_clear_wasi_stdin_buffer(self.ptr())
}

///|
/// Take captured stdout bytes (and clear buffer)
fn JITContext::take_wasi_stdout(self : JITContext) -> Bytes {
  @jit_ffi.c_jit_take_wasi_stdout(self.ptr())
}

///|
/// Take captured stderr bytes (and clear buffer)
fn JITContext::take_wasi_stderr(self : JITContext) -> Bytes {
  @jit_ffi.c_jit_take_wasi_stderr(self.ptr())
}

///|
pub fn alloc_memory(size : Int64) -> Int64 {
  @wasmoon_jit.alloc_memory(size)
}

///|
pub fn alloc_memory_desc(
  size_bytes : Int64,
  max_pages : Int?,
  is_memory64? : Bool = false,
  page_size_log2? : Int = 16,
  is_shared? : Bool = false,
) -> Int64 {
  @wasmoon_jit.alloc_memory_desc(
    size_bytes,
    max_pages,
    is_memory64~,
    page_size_log2~,
    is_shared~,
  )
}

///|
pub fn alloc_guarded_memory_desc(
  initial_pages : Int,
  max_pages : Int?,
) -> Int64 {
  @wasmoon_jit.alloc_guarded_memory_desc(initial_pages, max_pages)
}

///|
pub fn free_memory(mem_ptr : Int64) -> Unit {
  @wasmoon_jit.free_memory(mem_ptr)
}

///|
pub fn free_memory_desc(mem_desc_ptr : Int64) -> Unit {
  @wasmoon_jit.free_memory_desc(mem_desc_ptr)
}

///|
pub fn memory_init(mem_ptr : Int64, offset : Int64, data : Bytes) -> Bool {
  @wasmoon_jit.memory_init(mem_ptr, offset, data)
}

///|
pub fn memory_read(mem_ptr : Int64, offset : Int64, size : Int) -> Bytes {
  @wasmoon_jit.memory_read(mem_ptr, offset, size)
}

///|
pub fn get_fd_write_ptr() -> Int64 {
  @wasmoon_jit.get_fd_write_ptr()
}

///|
pub fn get_proc_exit_ptr() -> Int64 {
  @wasmoon_jit.get_proc_exit_ptr()
}

///|
pub fn get_fd_read_ptr() -> Int64 {
  @wasmoon_jit.get_fd_read_ptr()
}

///|
pub fn get_args_sizes_get_ptr() -> Int64 {
  @wasmoon_jit.get_args_sizes_get_ptr()
}

///|
pub fn get_args_get_ptr() -> Int64 {
  @wasmoon_jit.get_args_get_ptr()
}

///|
pub fn get_environ_sizes_get_ptr() -> Int64 {
  @wasmoon_jit.get_environ_sizes_get_ptr()
}

///|
pub fn get_environ_get_ptr() -> Int64 {
  @wasmoon_jit.get_environ_get_ptr()
}

///|
pub fn get_clock_time_get_ptr() -> Int64 {
  @wasmoon_jit.get_clock_time_get_ptr()
}

///|
pub fn get_random_get_ptr() -> Int64 {
  @wasmoon_jit.get_random_get_ptr()
}

///|
pub fn get_fd_close_ptr() -> Int64 {
  @wasmoon_jit.get_fd_close_ptr()
}

///|
pub fn get_fd_fdstat_get_ptr() -> Int64 {
  @wasmoon_jit.get_fd_fdstat_get_ptr()
}

///|
pub fn get_fd_prestat_get_ptr() -> Int64 {
  @wasmoon_jit.get_fd_prestat_get_ptr()
}

///|
pub fn get_fd_prestat_dir_name_ptr() -> Int64 {
  @wasmoon_jit.get_fd_prestat_dir_name_ptr()
}

///|
pub fn get_fd_seek_ptr() -> Int64 {
  @wasmoon_jit.get_fd_seek_ptr()
}

///|
pub fn get_fd_tell_ptr() -> Int64 {
  @wasmoon_jit.get_fd_tell_ptr()
}

///|
pub fn get_fd_sync_ptr() -> Int64 {
  @wasmoon_jit.get_fd_sync_ptr()
}

///|
pub fn get_fd_datasync_ptr() -> Int64 {
  @wasmoon_jit.get_fd_datasync_ptr()
}

///|
pub fn get_fd_filestat_get_ptr() -> Int64 {
  @wasmoon_jit.get_fd_filestat_get_ptr()
}

///|
pub fn get_fd_filestat_set_size_ptr() -> Int64 {
  @wasmoon_jit.get_fd_filestat_set_size_ptr()
}

///|
pub fn get_path_open_ptr() -> Int64 {
  @wasmoon_jit.get_path_open_ptr()
}

///|
pub fn get_path_create_directory_ptr() -> Int64 {
  @wasmoon_jit.get_path_create_directory_ptr()
}

///|
pub fn get_path_unlink_file_ptr() -> Int64 {
  @wasmoon_jit.get_path_unlink_file_ptr()
}

///|
pub fn get_path_remove_directory_ptr() -> Int64 {
  @wasmoon_jit.get_path_remove_directory_ptr()
}

///|
pub fn get_path_rename_ptr() -> Int64 {
  @wasmoon_jit.get_path_rename_ptr()
}

///|
pub fn get_clock_res_get_ptr() -> Int64 {
  @wasmoon_jit.get_clock_res_get_ptr()
}

///|
pub fn get_sched_yield_ptr() -> Int64 {
  @wasmoon_jit.get_sched_yield_ptr()
}

///|
pub fn get_proc_raise_ptr() -> Int64 {
  @wasmoon_jit.get_proc_raise_ptr()
}

///|
pub fn get_poll_oneoff_ptr() -> Int64 {
  @wasmoon_jit.get_poll_oneoff_ptr()
}

///|
pub fn get_fd_advise_ptr() -> Int64 {
  @wasmoon_jit.get_fd_advise_ptr()
}

///|
pub fn get_fd_allocate_ptr() -> Int64 {
  @wasmoon_jit.get_fd_allocate_ptr()
}

///|
pub fn get_fd_pread_ptr() -> Int64 {
  @wasmoon_jit.get_fd_pread_ptr()
}

///|
pub fn get_fd_pwrite_ptr() -> Int64 {
  @wasmoon_jit.get_fd_pwrite_ptr()
}

///|
pub fn get_fd_readdir_ptr() -> Int64 {
  @wasmoon_jit.get_fd_readdir_ptr()
}

///|
pub fn get_fd_renumber_ptr() -> Int64 {
  @wasmoon_jit.get_fd_renumber_ptr()
}

///|
pub fn get_fd_fdstat_set_flags_ptr() -> Int64 {
  @wasmoon_jit.get_fd_fdstat_set_flags_ptr()
}

///|
pub fn get_fd_fdstat_set_rights_ptr() -> Int64 {
  @wasmoon_jit.get_fd_fdstat_set_rights_ptr()
}

///|
pub fn get_fd_filestat_set_times_ptr() -> Int64 {
  @wasmoon_jit.get_fd_filestat_set_times_ptr()
}

///|
pub fn get_path_filestat_get_ptr() -> Int64 {
  @wasmoon_jit.get_path_filestat_get_ptr()
}

///|
pub fn get_path_filestat_set_times_ptr() -> Int64 {
  @wasmoon_jit.get_path_filestat_set_times_ptr()
}

///|
pub fn get_path_link_ptr() -> Int64 {
  @wasmoon_jit.get_path_link_ptr()
}

///|
pub fn get_path_readlink_ptr() -> Int64 {
  @wasmoon_jit.get_path_readlink_ptr()
}

///|
pub fn get_path_symlink_ptr() -> Int64 {
  @wasmoon_jit.get_path_symlink_ptr()
}

///|
pub fn get_sock_accept_ptr() -> Int64 {
  @wasmoon_jit.get_sock_accept_ptr()
}

///|
pub fn get_sock_recv_ptr() -> Int64 {
  @wasmoon_jit.get_sock_recv_ptr()
}

///|
pub fn get_sock_send_ptr() -> Int64 {
  @wasmoon_jit.get_sock_send_ptr()
}

///|
pub fn get_sock_shutdown_ptr() -> Int64 {
  @wasmoon_jit.get_sock_shutdown_ptr()
}

///|
pub fn get_spectest_print_ptr() -> Int64 {
  @wasmoon_jit.get_spectest_print_ptr()
}

///|
pub fn get_spectest_print_i32_ptr() -> Int64 {
  @wasmoon_jit.get_spectest_print_i32_ptr()
}

///|
pub fn get_spectest_print_i64_ptr() -> Int64 {
  @wasmoon_jit.get_spectest_print_i64_ptr()
}

///|
pub fn get_spectest_print_f32_ptr() -> Int64 {
  @wasmoon_jit.get_spectest_print_f32_ptr()
}

///|
pub fn get_spectest_print_f64_ptr() -> Int64 {
  @wasmoon_jit.get_spectest_print_f64_ptr()
}

///|
pub fn get_spectest_print_i32_f32_ptr() -> Int64 {
  @wasmoon_jit.get_spectest_print_i32_f32_ptr()
}

///|
pub fn get_spectest_print_f64_f64_ptr() -> Int64 {
  @wasmoon_jit.get_spectest_print_f64_f64_ptr()
}

///|
pub fn get_spectest_print_char_ptr() -> Int64 {
  @wasmoon_jit.get_spectest_print_char_ptr()
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
