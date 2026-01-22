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
} derive(Show)

///|
let wasi_exit_trap_code : Int = 100

///|
/// Low-level trap detail captured by the JIT signal handlers (best-effort).
pub struct TrapDetails {
  signal : Int
  pc : Int64
  lr : Int64
  fp : Int64
  frame_lr : Int64
  fault_addr : Int64
  brk_imm : Int
  func_idx : Int
}

///|
pub fn TrapDetails::new() -> TrapDetails {
  {
    signal: 0,
    pc: 0L,
    lr: 0L,
    fp: 0L,
    frame_lr: 0L,
    fault_addr: 0L,
    brk_imm: 0,
    func_idx: -1,
  }
}

///|
/// Get the last captured trap details (best-effort).
/// These fields are reset at the start of each JIT call.
pub fn get_last_trap_details() -> TrapDetails {
  {
    signal: @jit_ffi.c_jit_get_trap_signal(),
    pc: @jit_ffi.c_jit_get_trap_pc(),
    lr: @jit_ffi.c_jit_get_trap_lr(),
    fp: @jit_ffi.c_jit_get_trap_fp(),
    frame_lr: @jit_ffi.c_jit_get_trap_frame_lr(),
    fault_addr: @jit_ffi.c_jit_get_trap_fault_addr(),
    brk_imm: @jit_ffi.c_jit_get_trap_brk_imm(),
    func_idx: @jit_ffi.c_jit_get_trap_func_idx(),
  }
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
/// 99 = unknown trap
pub fn check_trap() -> Unit raise JITTrap {
  let code = @jit_ffi.c_jit_get_trap_code()
  if code != 0 {
    @jit_ffi.c_jit_clear_trap()
    let msg = match code {
      1 => "out of bounds memory access"
      2 => "call stack exhausted"
      3 => "unreachable"
      4 => "indirect call type mismatch"
      5 => "invalid conversion to integer"
      6 => "integer divide by zero"
      7 => "integer overflow"
      _ => "unknown trap"
    }
    raise JITTrap(msg)
  }
}

// ============ Memory Info ============

///|
/// Memory information for JIT execution
pub struct MemoryInfo {
  ptr : Int64 // Pointer to `wasmoon_memory_t` (memory descriptor)
  size : Int64 // Initial size in bytes (informational)
  max_pages : Int? // Max pages (None = unlimited)
}

///|
/// Create a new MemoryInfo
pub fn MemoryInfo::new(
  ptr : Int64,
  size : Int64,
  max_pages : Int?,
) -> MemoryInfo {
  { ptr, size, max_pages }
}

// ============ JIT Context Wrapper ============

///|
/// JIT execution context (JIT ABI) - GC managed
/// Uses Standard on-demand loading from vmctx:
/// +0: memory_base, +8: memory_size, +16: func_table, +24: table0_base
/// Only X19 caches vmctx; all other values are loaded on-demand.
/// Memory is automatically freed when the object is garbage collected
priv struct JITContext {
  ctx : @jit_ffi.JITContext
  // Trampoline cache: maps signature hash to generated trampoline
  // Signature hash = hash of (param_types, result_types)
  trampoline_cache : Map[Int64, ExecCode]
}

///|
/// Create a new JIT context - GC managed
fn JITContext::new(total_funcs : Int) -> JITContext? {
  let ctx = @jit_ffi.c_jit_alloc_context_managed(total_funcs)
  // Check if allocation succeeded by verifying the pointer is valid
  if @jit_ffi.c_jit_context_ptr(ctx) != 0L {
    Some(JITContext::{ ctx, trampoline_cache: Map::new() })
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
/// Set GC heap in the context for inline allocation
/// This initializes gc_heap_ptr and gc_heap_limit in VMContext
fn JITContext::set_gc_heap(self : JITContext, heap_ptr : Int64) -> Unit {
  @jit_ffi.c_jit_ctx_set_gc_heap(self.ptr(), heap_ptr)
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
/// Get the function count
fn JITContext::get_func_count(self : JITContext) -> Int {
  @jit_ffi.c_jit_ctx_get_func_count(self.ptr())
}

///|
/// Set multiple indirect tables (for multi-table support)
/// jit_tables: Array of JITTable? from Store
/// This enables proper multi-table support where each call_indirect can specify which table to use
fn JITContext::set_table_pointers(
  self : JITContext,
  jit_tables : Array[JITTable?],
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
        table_ptrs[i] = jit_table.table_ptr
        table_sizes[i] = jit_table.size
        table_max_sizes[i] = jit_table.max.unwrap_or(-1) // -1 = unlimited
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
  memories : Array[MemoryInfo],
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
/// Allocate linear memory for WASM (returns 0 on failure)
/// NOTE: If you set the memory to a JITContext (via set_memory), the context
/// takes ownership and its finalizer will free the memory. Do NOT call
/// free_memory after that.
pub fn alloc_memory(size : Int64) -> Int64 {
  @jit_ffi.c_jit_alloc_memory(size)
}

///|
/// Allocate a `wasmoon_memory_t` descriptor with owned backing memory.
pub fn alloc_memory_desc(
  size_bytes : Int64,
  max_pages : Int?,
  is_memory64? : Bool = false,
  page_size_log2? : Int = 16,
  is_shared? : Bool = false,
) -> Int64 {
  @jit_ffi.c_jit_alloc_memory_desc(
    size_bytes,
    max_pages.unwrap_or(-1),
    if is_memory64 {
      1
    } else {
      0
    },
    page_size_log2,
    if is_shared {
      1
    } else {
      0
    },
  )
}

///|
/// Allocate a guarded (reserved) memory descriptor for memory32 memory0.
/// This is required for bounds-check elimination; out-of-bounds accesses trap via guard pages.
pub fn alloc_guarded_memory_desc(
  initial_pages : Int,
  max_pages : Int?,
) -> Int64 {
  @jit_ffi.c_jit_alloc_guarded_memory_desc(
    initial_pages.to_int64(),
    max_pages.unwrap_or(-1).to_int64(),
  )
}

///|
pub fn free_memory(mem_ptr : Int64) -> Unit {
  @jit_ffi.c_jit_free_memory(mem_ptr)
}

///|
pub fn free_memory_desc(mem_desc_ptr : Int64) -> Unit {
  @jit_ffi.c_jit_free_memory_desc(mem_desc_ptr)
}

///|
/// Initialize memory with data at offset
pub fn memory_init(mem_ptr : Int64, offset : Int64, data : Bytes) -> Bool {
  let size = data.length()
  if size == 0 {
    return true
  }
  let bytes = FixedArray::make(size, b'\x00')
  for i in 0..<size {
    bytes[i] = data[i]
  }
  @jit_ffi.c_jit_memory_init(mem_ptr, offset, bytes, size) == 0
}

///|
/// Read `size` bytes from linear memory at offset
pub fn memory_read(mem_ptr : Int64, offset : Int64, size : Int) -> Bytes {
  if mem_ptr == 0L || size <= 0 {
    return b""
  }
  let out = FixedArray::make(size, b'\x00')
  let rc = @jit_ffi.c_jit_memory_read(mem_ptr, offset, out, size)
  if rc != 0 {
    return b""
  }
  let arr : Array[Byte] = Array::make(size, b'\x00')
  for i in 0..<size {
    arr[i] = out[i]
  }
  Bytes::from_array(arr)
}

// NOTE: No free() method needed - GC handles cleanup automatically!

// ============ Shared JIT Indirect Table ============

///|
/// Shared indirect table that can be used by multiple JIT modules
/// This enables cross-module table sharing and runtime modifications
struct JITTable {
  table_ptr : Int64 // Pointer to the shared C-side table
  size : Int
  max : Int?
} derive(Show)

///|
/// Create a new shared JIT table
/// Note: size 0 is valid (empty table that can grow later)
pub fn JITTable::new(size : Int, max : Int?) -> JITTable? {
  if size < 0 {
    return None
  }
  // For size 0, allocate with capacity 1 to avoid null pointer issues
  // The actual size is tracked separately
  let alloc_size = if size == 0 { 1 } else { size }
  let table_ptr = @jit_ffi.c_jit_alloc_shared_indirect_table(alloc_size)
  if table_ptr == 0L {
    return None
  }
  Some(JITTable::{ table_ptr, size, max })
}

///|
/// Set an entry in the shared table
/// table_idx: index in the table
/// func_ptr: pointer to the function
/// type_hash: type hash for type checking
pub fn JITTable::set(
  self : JITTable,
  table_idx : Int,
  func_ptr : Int64,
  type_hash : Int,
) -> Unit {
  @jit_ffi.c_jit_shared_table_set(
    self.table_ptr,
    table_idx,
    func_ptr,
    type_hash,
  )
}

///|
/// Get the table size
pub fn JITTable::get_size(self : JITTable) -> Int {
  self.size
}

///|
/// Get the table max size
pub fn JITTable::get_max(self : JITTable) -> Int? {
  self.max
}

///|
/// Get fd_write trampoline pointer
pub fn get_fd_write_ptr() -> Int64 {
  @jit_ffi.c_jit_get_fd_write_ptr()
}

///|
/// Get proc_exit trampoline pointer
pub fn get_proc_exit_ptr() -> Int64 {
  @jit_ffi.c_jit_get_proc_exit_ptr()
}

///|
/// Get fd_read trampoline pointer
pub fn get_fd_read_ptr() -> Int64 {
  @jit_ffi.c_jit_get_fd_read_ptr()
}

///|
/// Get args_sizes_get trampoline pointer
pub fn get_args_sizes_get_ptr() -> Int64 {
  @jit_ffi.c_jit_get_args_sizes_get_ptr()
}

///|
/// Get args_get trampoline pointer
pub fn get_args_get_ptr() -> Int64 {
  @jit_ffi.c_jit_get_args_get_ptr()
}

///|
/// Get environ_sizes_get trampoline pointer
pub fn get_environ_sizes_get_ptr() -> Int64 {
  @jit_ffi.c_jit_get_environ_sizes_get_ptr()
}

///|
/// Get environ_get trampoline pointer
pub fn get_environ_get_ptr() -> Int64 {
  @jit_ffi.c_jit_get_environ_get_ptr()
}

///|
/// Get clock_time_get trampoline pointer
pub fn get_clock_time_get_ptr() -> Int64 {
  @jit_ffi.c_jit_get_clock_time_get_ptr()
}

///|
/// Get random_get trampoline pointer
pub fn get_random_get_ptr() -> Int64 {
  @jit_ffi.c_jit_get_random_get_ptr()
}

///|
/// Get fd_close trampoline pointer
pub fn get_fd_close_ptr() -> Int64 {
  @jit_ffi.c_jit_get_fd_close_ptr()
}

///|
/// Get fd_fdstat_get trampoline pointer
pub fn get_fd_fdstat_get_ptr() -> Int64 {
  @jit_ffi.c_jit_get_fd_fdstat_get_ptr()
}

///|
/// Get fd_prestat_get trampoline pointer
pub fn get_fd_prestat_get_ptr() -> Int64 {
  @jit_ffi.c_jit_get_fd_prestat_get_ptr()
}

///|
/// Get fd_prestat_dir_name trampoline pointer
pub fn get_fd_prestat_dir_name_ptr() -> Int64 {
  @jit_ffi.c_jit_get_fd_prestat_dir_name_ptr()
}

///|
/// Get fd_seek trampoline pointer
pub fn get_fd_seek_ptr() -> Int64 {
  @jit_ffi.c_jit_get_fd_seek_ptr()
}

///|
/// Get fd_tell trampoline pointer
pub fn get_fd_tell_ptr() -> Int64 {
  @jit_ffi.c_jit_get_fd_tell_ptr()
}

///|
/// Get fd_sync trampoline pointer
pub fn get_fd_sync_ptr() -> Int64 {
  @jit_ffi.c_jit_get_fd_sync_ptr()
}

///|
/// Get fd_datasync trampoline pointer
pub fn get_fd_datasync_ptr() -> Int64 {
  @jit_ffi.c_jit_get_fd_datasync_ptr()
}

///|
/// Get fd_filestat_get trampoline pointer
pub fn get_fd_filestat_get_ptr() -> Int64 {
  @jit_ffi.c_jit_get_fd_filestat_get_ptr()
}

///|
/// Get fd_filestat_set_size trampoline pointer
pub fn get_fd_filestat_set_size_ptr() -> Int64 {
  @jit_ffi.c_jit_get_fd_filestat_set_size_ptr()
}

///|
/// Get path_open trampoline pointer
pub fn get_path_open_ptr() -> Int64 {
  @jit_ffi.c_jit_get_path_open_ptr()
}

///|
/// Get path_create_directory trampoline pointer
pub fn get_path_create_directory_ptr() -> Int64 {
  @jit_ffi.c_jit_get_path_create_directory_ptr()
}

///|
/// Get path_unlink_file trampoline pointer
pub fn get_path_unlink_file_ptr() -> Int64 {
  @jit_ffi.c_jit_get_path_unlink_file_ptr()
}

///|
/// Get path_remove_directory trampoline pointer
pub fn get_path_remove_directory_ptr() -> Int64 {
  @jit_ffi.c_jit_get_path_remove_directory_ptr()
}

///|
/// Get path_rename trampoline pointer
pub fn get_path_rename_ptr() -> Int64 {
  @jit_ffi.c_jit_get_path_rename_ptr()
}

///|
/// Get clock_res_get trampoline pointer
pub fn get_clock_res_get_ptr() -> Int64 {
  @jit_ffi.c_jit_get_clock_res_get_ptr()
}

///|
/// Get sched_yield trampoline pointer
pub fn get_sched_yield_ptr() -> Int64 {
  @jit_ffi.c_jit_get_sched_yield_ptr()
}

///|
/// Get proc_raise trampoline pointer
pub fn get_proc_raise_ptr() -> Int64 {
  @jit_ffi.c_jit_get_proc_raise_ptr()
}

///|
/// Get poll_oneoff trampoline pointer
pub fn get_poll_oneoff_ptr() -> Int64 {
  @jit_ffi.c_jit_get_poll_oneoff_ptr()
}

///|
/// Get fd_advise trampoline pointer (stub)
pub fn get_fd_advise_ptr() -> Int64 {
  @jit_ffi.c_jit_get_fd_advise_ptr()
}

///|
/// Get fd_allocate trampoline pointer (stub)
pub fn get_fd_allocate_ptr() -> Int64 {
  @jit_ffi.c_jit_get_fd_allocate_ptr()
}

///|
/// Get fd_pread trampoline pointer (stub)
pub fn get_fd_pread_ptr() -> Int64 {
  @jit_ffi.c_jit_get_fd_pread_ptr()
}

///|
/// Get fd_pwrite trampoline pointer (stub)
pub fn get_fd_pwrite_ptr() -> Int64 {
  @jit_ffi.c_jit_get_fd_pwrite_ptr()
}

///|
/// Get fd_readdir trampoline pointer (stub)
pub fn get_fd_readdir_ptr() -> Int64 {
  @jit_ffi.c_jit_get_fd_readdir_ptr()
}

///|
/// Get fd_renumber trampoline pointer (stub)
pub fn get_fd_renumber_ptr() -> Int64 {
  @jit_ffi.c_jit_get_fd_renumber_ptr()
}

///|
/// Get fd_fdstat_set_flags trampoline pointer (stub)
pub fn get_fd_fdstat_set_flags_ptr() -> Int64 {
  @jit_ffi.c_jit_get_fd_fdstat_set_flags_ptr()
}

///|
/// Get fd_fdstat_set_rights trampoline pointer (stub)
pub fn get_fd_fdstat_set_rights_ptr() -> Int64 {
  @jit_ffi.c_jit_get_fd_fdstat_set_rights_ptr()
}

///|
/// Get fd_filestat_set_times trampoline pointer (stub)
pub fn get_fd_filestat_set_times_ptr() -> Int64 {
  @jit_ffi.c_jit_get_fd_filestat_set_times_ptr()
}

///|
/// Get path_filestat_get trampoline pointer (stub)
pub fn get_path_filestat_get_ptr() -> Int64 {
  @jit_ffi.c_jit_get_path_filestat_get_ptr()
}

///|
/// Get path_filestat_set_times trampoline pointer (stub)
pub fn get_path_filestat_set_times_ptr() -> Int64 {
  @jit_ffi.c_jit_get_path_filestat_set_times_ptr()
}

///|
/// Get path_link trampoline pointer (stub)
pub fn get_path_link_ptr() -> Int64 {
  @jit_ffi.c_jit_get_path_link_ptr()
}

///|
/// Get path_readlink trampoline pointer (stub)
pub fn get_path_readlink_ptr() -> Int64 {
  @jit_ffi.c_jit_get_path_readlink_ptr()
}

///|
/// Get path_symlink trampoline pointer (stub)
pub fn get_path_symlink_ptr() -> Int64 {
  @jit_ffi.c_jit_get_path_symlink_ptr()
}

///|
/// Get sock_accept trampoline pointer (stub - returns ENOTSUP)
pub fn get_sock_accept_ptr() -> Int64 {
  @jit_ffi.c_jit_get_sock_accept_ptr()
}

///|
/// Get sock_recv trampoline pointer (stub - returns ENOTSUP)
pub fn get_sock_recv_ptr() -> Int64 {
  @jit_ffi.c_jit_get_sock_recv_ptr()
}

///|
/// Get sock_send trampoline pointer (stub - returns ENOTSUP)
pub fn get_sock_send_ptr() -> Int64 {
  @jit_ffi.c_jit_get_sock_send_ptr()
}

///|
/// Get sock_shutdown trampoline pointer (stub - returns ENOTSUP)
pub fn get_sock_shutdown_ptr() -> Int64 {
  @jit_ffi.c_jit_get_sock_shutdown_ptr()
}

///|
/// Get spectest print trampoline pointer
pub fn get_spectest_print_ptr() -> Int64 {
  @jit_ffi.c_jit_get_spectest_print_ptr()
}

///|
/// Get spectest print_i32 trampoline pointer
pub fn get_spectest_print_i32_ptr() -> Int64 {
  @jit_ffi.c_jit_get_spectest_print_i32_ptr()
}

///|
/// Get spectest print_i64 trampoline pointer
pub fn get_spectest_print_i64_ptr() -> Int64 {
  @jit_ffi.c_jit_get_spectest_print_i64_ptr()
}

///|
/// Get spectest print_f32 trampoline pointer
pub fn get_spectest_print_f32_ptr() -> Int64 {
  @jit_ffi.c_jit_get_spectest_print_f32_ptr()
}

///|
/// Get spectest print_f64 trampoline pointer
pub fn get_spectest_print_f64_ptr() -> Int64 {
  @jit_ffi.c_jit_get_spectest_print_f64_ptr()
}

///|
/// Get spectest print_i32_f32 trampoline pointer
pub fn get_spectest_print_i32_f32_ptr() -> Int64 {
  @jit_ffi.c_jit_get_spectest_print_i32_f32_ptr()
}

///|
/// Get spectest print_f64_f64 trampoline pointer
pub fn get_spectest_print_f64_f64_ptr() -> Int64 {
  @jit_ffi.c_jit_get_spectest_print_f64_f64_ptr()
}

///|
/// Get spectest print_char trampoline pointer
pub fn get_spectest_print_char_ptr() -> Int64 {
  @jit_ffi.c_jit_get_spectest_print_char_ptr()
}

// ============ Executable Code Block ============

///|
/// GC-managed executable code block wrapper
/// Memory is automatically freed when the object is garbage collected
pub struct ExecCode(@jit_ffi.ExecCode)

///|
/// Allocate and copy code to executable memory (GC-managed)
pub fn ExecCode::new(code : Array[Int]) -> ExecCode? {
  let size = code.length()
  if size == 0 {
    return None
  }
  // Copy code bytes
  let bytes = FixedArray::make(size, b'\x00')
  for i, b in code {
    bytes[i] = b.to_byte()
  }
  let ec = @jit_ffi.c_jit_alloc_exec_managed(bytes, size)
  // Check if allocation succeeded by verifying the pointer is valid
  if @jit_ffi.c_jit_exec_code_ptr(ec) != 0L {
    Some(ExecCode(ec))
  } else {
    None
  }
}

///|
/// Get the function pointer from this executable code
pub fn ExecCode::ptr(self : ExecCode) -> Int64 {
  @jit_ffi.c_jit_exec_code_ptr(self.0)
}

// NOTE: No free() method needed - GC handles cleanup automatically!

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
  let num_params = param_types.length() // Number of actual WASM parameters

  // For results, V128 needs 2 slots
  let mut num_result_slots = 0
  for result_type in result_types {
    if result_type is @types.ValueType::V128 {
      num_result_slots = num_result_slots + 2
    } else {
      num_result_slots = num_result_slots + 1
    }
  }

  // Convert param_types to int codes for trampoline generation
  // Note: param_type_codes uses the original parameter count, not expanded slot count
  let param_type_codes = FixedArray::make(num_params.max(1), 0)
  for i in 0..<num_params {
    param_type_codes[i] = value_type_to_code(param_types[i])
  }

  // Convert result_types to int codes for trampoline generation
  let result_type_codes = FixedArray::make(result_types.length().max(1), 0)
  for i in 0..<result_types.length() {
    result_type_codes[i] = value_type_to_code(result_types[i])
  }

  // Compute signature hash for trampoline cache lookup
  let num_results = result_types.length()
  let sig_hash = compute_signature_hash(
    param_type_codes, num_params, result_type_codes, num_results,
  )

  // Get or generate trampoline
  let trampoline_ptr = match self.trampoline_cache.get(sig_hash) {
    Some(trampoline) => trampoline.ptr()
    None => {
      // Generate trampoline using emit_entry_trampoline
      let param_codes_arr : Array[Int] = []
      for i in 0..<num_params {
        param_codes_arr.push(param_type_codes[i])
      }
      let result_codes_arr : Array[Int] = []
      for i in 0..<num_results {
        result_codes_arr.push(result_type_codes[i])
      }
      let mc = @emit.emit_entry_trampoline(param_codes_arr, result_codes_arr)
      let code_ints = mc.get_bytes()
      let trampoline = ExecCode::new(code_ints)
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
    if trap_code == wasi_exit_trap_code {
      let raw_code = @jit_ffi.c_jit_get_wasi_exit_code(self.ptr())
      @jit_ffi.c_jit_clear_wasi_exit(self.ptr())
      let exit_code = if raw_code < 0 { 0 } else { raw_code }
      raise JITExit(exit_code)
    }
    let msg = match trap_code {
      1 => "out of bounds memory access"
      2 => "call stack exhausted"
      3 => "unreachable"
      4 => "indirect call type mismatch"
      5 => "invalid conversion to integer"
      6 => "integer divide by zero"
      7 => "integer overflow"
      _ => "unknown trap"
    }
    raise JITTrap(msg)
  }

  // Copy results back from values_vec (results start after args)
  // V128 results take 2 slots
  for i in 0..<num_result_slots {
    results[i] = values_vec[num_arg_slots + i]
  }
}

///|
/// Convert ValueType to type code for trampoline generation
/// 0=I32, 1=I64, 2=F32, 3=F64, 4=V128
fn value_type_to_code(ty : @types.ValueType) -> Int {
  match ty {
    I32 => 0
    I64 => 1
    F32 => 2
    F64 => 3
    V128 => 4
    // Reference types are 64-bit integer values (indices/pointers)
    FuncRef
    | ExternRef
    | RefFunc
    | RefExtern
    | RefFuncTyped(_)
    | RefNullFuncTyped(_)
    | AnyRef
    | ExnRef
    | NullRef
    | NullFuncRef
    | NullExnRef
    | NullExternRef
    // GC reference types - also 64-bit
    | RefStruct(_)
    | RefNullStruct(_)
    | RefArray(_)
    | RefNullArray(_)
    | RefAny
    | RefEq
    | RefNullEq
    | RefI31
    | RefNullI31
    | RefStructAbs
    | RefArrayAbs
    | StructRef
    | ArrayRef
    | RefNone => 1
  }
}

///|
/// Compute a hash for function signature (param_types, result_types)
/// Used for trampoline cache lookup
fn compute_signature_hash(
  param_types : FixedArray[Int],
  num_params : Int,
  result_types : FixedArray[Int],
  num_results : Int,
) -> Int64 {
  // Simple FNV-1a hash
  let mut hash = 0xcbf29ce484222325L // FNV offset basis
  let fnv_prime = 0x100000001b3L

  // Hash number of params
  hash = hash ^ num_params.to_int64()
  hash = hash * fnv_prime

  // Hash param types
  for i in 0..<num_params {
    hash = hash ^ param_types[i].to_int64()
    hash = hash * fnv_prime
  }

  // Hash separator
  hash = hash ^ 0xffL
  hash = hash * fnv_prime

  // Hash number of results
  hash = hash ^ num_results.to_int64()
  hash = hash * fnv_prime

  // Hash result types
  for i in 0..<num_results {
    hash = hash ^ result_types[i].to_int64()
    hash = hash * fnv_prime
  }
  hash
}
