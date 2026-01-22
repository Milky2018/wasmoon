///|
/// JIT runtime FFI for executable memory management and code execution
/// These functions call C functions defined in ffi_jit.c

// ============ Trap Handling ============

///|
/// Get trap code (0 = no trap, 1 = out of bounds memory access)
pub extern "c" fn c_jit_get_trap_code() -> Int = "wasmoon_jit_get_trap_code"

///|
/// Clear trap code
pub extern "c" fn c_jit_clear_trap() -> Unit = "wasmoon_jit_clear_trap"

///|
/// Get last trap signal number (e.g. SIGSEGV/SIGBUS/SIGTRAP), or 0 if none
pub extern "c" fn c_jit_get_trap_signal() -> Int = "wasmoon_jit_get_trap_signal"

///|
/// Get last trap PC (instruction address), or 0 if unavailable
pub extern "c" fn c_jit_get_trap_pc() -> Int64 = "wasmoon_jit_get_trap_pc"

///|
/// Get last trap LR (return address), or 0 if unavailable
pub extern "c" fn c_jit_get_trap_lr() -> Int64 = "wasmoon_jit_get_trap_lr"

///|
/// Get last trap FP (frame pointer), or 0 if unavailable
pub extern "c" fn c_jit_get_trap_fp() -> Int64 = "wasmoon_jit_get_trap_fp"

///|
/// Get caller return address from the frame record ([fp + 8]), or 0 if unavailable
pub extern "c" fn c_jit_get_trap_frame_lr() -> Int64 = "wasmoon_jit_get_trap_frame_lr"

///|
/// Get last trap fault address (SIGSEGV/SIGBUS si_addr), or 0 if N/A
pub extern "c" fn c_jit_get_trap_fault_addr() -> Int64 = "wasmoon_jit_get_trap_fault_addr"

///|
/// Get BRK immediate decoded for SIGTRAP, or -1 if N/A
pub extern "c" fn c_jit_get_trap_brk_imm() -> Int = "wasmoon_jit_get_trap_brk_imm"

///|
/// Get best-effort wasm func_idx at trap time, or -1 if unknown
pub extern "c" fn c_jit_get_trap_func_idx() -> Int = "wasmoon_jit_get_trap_func_idx"

// ============ GC-managed JITContext ============

///|
/// GC-managed JIT context object
/// The context is automatically freed when the object is garbage collected
pub type JITContext

///|
/// Allocate GC-managed JIT context
pub extern "c" fn c_jit_alloc_context_managed(func_count : Int) -> JITContext = "wasmoon_jit_alloc_context_managed"

///|
/// Get the context pointer from a GC-managed JITContext object
#borrow(jit_context)
pub extern "c" fn c_jit_context_ptr(jit_context : JITContext) -> Int64 = "wasmoon_jit_context_ptr"

///|
/// Set a function pointer in the context's function table
pub extern "c" fn c_jit_ctx_set_func(
  ctx_ptr : Int64,
  idx : Int,
  func_ptr : Int64,
) -> Unit = "wasmoon_jit_ctx_set_func"

///|
/// Copy data to linear memory at offset
#borrow(data)
pub extern "c" fn c_jit_memory_init(
  mem_ptr : Int64,
  offset : Int64,
  data : FixedArray[Byte],
  size : Int,
) -> Int = "wasmoon_jit_memory_init"

///|
/// Copy data from linear memory at offset into `out`
#borrow(out)
pub extern "c" fn c_jit_memory_read(
  mem_ptr : Int64,
  offset : Int64,
  out : FixedArray[Byte],
  size : Int,
) -> Int = "wasmoon_jit_memory_read"

///|
/// Set memory0 in the context
pub extern "c" fn c_jit_ctx_set_memory(
  ctx_ptr : Int64,
  mem0_ptr : Int64,
) -> Unit = "wasmoon_jit_ctx_set_memory"

///|
/// Get memory base pointer for memidx
pub extern "c" fn c_jit_ctx_get_memory_ptr(
  ctx_ptr : Int64,
  memidx : Int,
) -> Int64 = "wasmoon_jit_ctx_get_memory_ptr"

///|
/// Get memory size in bytes for memidx
pub extern "c" fn c_jit_ctx_get_memory_size(
  ctx_ptr : Int64,
  memidx : Int,
) -> Int64 = "wasmoon_jit_ctx_get_memory_size"

///|
/// Allocate linear memory for generic buffers (globals, etc.)
pub extern "c" fn c_jit_alloc_memory(size : Int64) -> Int64 = "wasmoon_jit_alloc_memory"

///|
/// Allocate a `wasmoon_memory_t` descriptor with an owned backing allocation.
/// max_pages is interpreted by the runtime; -1 means "unknown/unlimited".
pub extern "c" fn c_jit_alloc_memory_desc(
  size_bytes : Int64,
  max_pages : Int,
  is_memory64 : Int,
  page_size_log2 : Int,
  is_shared : Int,
) -> Int64 = "wasmoon_jit_alloc_memory_desc"

///|
/// Free a `wasmoon_memory_t` descriptor and its owned backing.
pub extern "c" fn c_jit_free_memory_desc(mem_ptr : Int64) -> Unit = "wasmoon_jit_free_memory_desc"

///|
/// Get base pointer from a `wasmoon_memory_t` descriptor.
pub extern "c" fn c_mem_desc_get_base(mem_desc_ptr : Int64) -> Int64 = "wasmoon_mem_desc_get_base"

///|
/// Get current length in bytes from a `wasmoon_memory_t` descriptor.
pub extern "c" fn c_mem_desc_get_len(mem_desc_ptr : Int64) -> Int64 = "wasmoon_mem_desc_get_len"

///|
/// Grow a `wasmoon_memory_t` descriptor by `delta_pages`.
/// Returns old size in pages on success, or -1 on failure.
pub extern "c" fn c_mem_desc_grow(
  mem_desc_ptr : Int64,
  delta_pages : Int,
  max_pages : Int,
) -> Int = "wasmoon_mem_desc_grow"

///|
/// Copy bytes from memory descriptor at offset into `out`.
#borrow(out)
pub extern "c" fn c_mem_desc_read(
  mem_desc_ptr : Int64,
  offset : Int64,
  out : FixedArray[Byte],
  size : Int,
) -> Int = "wasmoon_mem_desc_read"

///|
/// Copy bytes from `data` into memory descriptor at offset.
#borrow(data)
pub extern "c" fn c_mem_desc_write(
  mem_desc_ptr : Int64,
  offset : Int64,
  data : FixedArray[Byte],
  size : Int,
) -> Int = "wasmoon_mem_desc_write"

///|
/// memmove within the same memory descriptor.
pub extern "c" fn c_mem_desc_memmove(
  mem_desc_ptr : Int64,
  dst : Int64,
  src : Int64,
  size : Int,
) -> Int = "wasmoon_mem_desc_memmove"

///|
/// memset within the same memory descriptor.
pub extern "c" fn c_mem_desc_memset(
  mem_desc_ptr : Int64,
  dst : Int64,
  val : Int,
  size : Int,
) -> Int = "wasmoon_mem_desc_memset"

///|
/// Allocate guarded memory into a standalone descriptor.
/// Returns: `wasmoon_memory_t*` on success, 0 on failure.
pub extern "c" fn c_jit_alloc_guarded_memory_desc(
  initial_pages : Int64,
  max_pages : Int64,
) -> Int64 = "wasmoon_jit_alloc_guarded_memory_desc"

///|
/// Allocate guarded memory with mmap for bounds check elimination
/// Memory is allocated with guard pages (PROT_NONE) after the accessible region
/// Access to guard pages triggers SIGSEGV which is caught and converted to a trap
/// Parameters:
///   ctx_ptr: JIT context pointer
///   initial_pages: Initial memory size in WASM pages (64KB each)
///   max_pages: Maximum memory size in WASM pages (-1 or 0 for default 4GB reservation)
/// Returns: memory pointer on success, 0 on failure
pub extern "c" fn c_jit_ctx_alloc_guarded_memory(
  ctx_ptr : Int64,
  initial_pages : Int64,
  max_pages : Int64,
) -> Int64 = "wasmoon_jit_ctx_alloc_guarded_memory"

///|
/// Free linear memory
pub extern "c" fn c_jit_free_memory(mem_ptr : Int64) -> Unit = "wasmoon_jit_free_memory"

///|
/// Get table_grow function pointer for JIT
/// Signature: table_grow(ctx: *jit_context_t, table_idx: i32, delta: i64, init_value: i64) -> i32
pub extern "c" fn c_jit_get_table_grow_ptr() -> Int64 = "wasmoon_jit_get_table_grow_ptr"

// ============ Multi-Memory Operations (with memidx) ============

///|
/// Get memory_grow function pointer for JIT (multi-memory)
/// Signature: memory_grow(ctx: *jit_context_t, memidx: i32, delta: i32, max_pages: i32) -> i32
pub extern "c" fn c_jit_get_memory_grow_ptr() -> Int64 = "wasmoon_jit_get_memory_grow_ptr"

///|
/// Get memory_size function pointer for JIT (multi-memory)
/// Signature: memory_size(ctx: *jit_context_t, memidx: i32) -> i32
pub extern "c" fn c_jit_get_memory_size_ptr() -> Int64 = "wasmoon_jit_get_memory_size_ptr"

///|
/// Get memory_fill function pointer for JIT (multi-memory)
/// Signature: memory_fill(ctx: *jit_context_t, memidx: i32, dst: i32, val: i32, size: i32) -> void
pub extern "c" fn c_jit_get_memory_fill_ptr() -> Int64 = "wasmoon_jit_get_memory_fill_ptr"

///|
/// Get memory_copy function pointer for JIT (multi-memory)
/// Signature: memory_copy(ctx: *jit_context_t, dst_memidx: i32, src_memidx: i32, dst: i32, src: i32, size: i32) -> void
pub extern "c" fn c_jit_get_memory_copy_ptr() -> Int64 = "wasmoon_jit_get_memory_copy_ptr"

///|
/// Get memory_init function pointer for JIT
/// Signature: memory_init(ctx: *jit_context_t, memidx: i32, data_idx: i32, dst: i32, src: i32, size: i32) -> void
pub extern "c" fn c_jit_get_memory_init_ptr() -> Int64 = "wasmoon_jit_get_memory_init_ptr"

///|
/// Get data_drop function pointer for JIT
/// Signature: data_drop(ctx: *jit_context_t, data_idx: i32) -> void
pub extern "c" fn c_jit_get_data_drop_ptr() -> Int64 = "wasmoon_jit_get_data_drop_ptr"

///|
/// Get table_fill function pointer for JIT
/// Signature: table_fill(ctx: *jit_context_t, table_idx: i32, dst: i32, val: i64, size: i32) -> void
pub extern "c" fn c_jit_get_table_fill_ptr() -> Int64 = "wasmoon_jit_get_table_fill_ptr"

///|
/// Get table_copy function pointer for JIT
/// Signature: table_copy(ctx: *jit_context_t, dst_table_idx: i32, src_table_idx: i32, dst: i32, src: i32, size: i32) -> void
pub extern "c" fn c_jit_get_table_copy_ptr() -> Int64 = "wasmoon_jit_get_table_copy_ptr"

///|
/// Get table_init function pointer for JIT
/// Signature: table_init(ctx: *jit_context_t, table_idx: i32, elem_idx: i32, dst: i32, src: i32, size: i32) -> void
pub extern "c" fn c_jit_get_table_init_ptr() -> Int64 = "wasmoon_jit_get_table_init_ptr"

///|
/// Get elem_drop function pointer for JIT
/// Signature: elem_drop(ctx: *jit_context_t, elem_idx: i32) -> void
pub extern "c" fn c_jit_get_elem_drop_ptr() -> Int64 = "wasmoon_jit_get_elem_drop_ptr"

///|
/// Configure JIT context with multiple memories (for multi-memory support)
/// memory_ptrs: FixedArray of Int64 (wasmoon_memory_t* pointers)
/// memory_count: Number of memories
#borrow(memory_ptrs)
pub extern "c" fn c_jit_ctx_set_memory_pointers(
  ctx_ptr : Int64,
  memory_ptrs : FixedArray[Int64],
  memory_count : Int,
) -> Unit = "wasmoon_jit_ctx_set_memory_pointers"

///|
/// Set globals array in the context
pub extern "c" fn c_jit_ctx_set_globals(
  ctx_ptr : Int64,
  globals_ptr : Int64,
) -> Unit = "wasmoon_jit_ctx_set_globals"

///|
/// Get function table base address from context
pub extern "c" fn c_jit_ctx_get_func_table(ctx_ptr : Int64) -> Int64 = "wasmoon_jit_ctx_get_func_table"

///|
/// Get function count from context
pub extern "c" fn c_jit_ctx_get_func_count(ctx_ptr : Int64) -> Int = "wasmoon_jit_ctx_get_func_count"

///|
/// Allocate indirect table for context
pub extern "c" fn c_jit_ctx_alloc_indirect_table(
  ctx_ptr : Int64,
  count : Int,
) -> Int = "wasmoon_jit_ctx_alloc_indirect_table"

///|
/// Set an entry in indirect table (table_idx -> func_table[func_idx])
/// type_idx: the type index of the function (for type checking)
pub extern "c" fn c_jit_ctx_set_indirect(
  ctx_ptr : Int64,
  table_idx : Int,
  func_idx : Int,
  type_idx : Int,
) -> Unit = "wasmoon_jit_ctx_set_indirect"

// ============ Shared Indirect Table ============

///|
/// Allocate a shared indirect table that can be used by multiple JIT modules
pub extern "c" fn c_jit_alloc_shared_indirect_table(count : Int) -> Int64 = "wasmoon_jit_alloc_shared_indirect_table"

///|
/// Free a shared indirect table
pub extern "c" fn c_jit_free_shared_indirect_table(table_ptr : Int64) -> Unit = "wasmoon_jit_free_shared_indirect_table"

///|
/// Set an entry in a shared indirect table
pub extern "c" fn c_jit_shared_table_set(
  table_ptr : Int64,
  table_idx : Int,
  func_ptr : Int64,
  type_hash : Int,
) -> Unit = "wasmoon_jit_shared_table_set"

///|
/// Configure a JIT context to use a shared indirect table
pub extern "c" fn c_jit_ctx_use_shared_table(
  ctx_ptr : Int64,
  shared_table_ptr : Int64,
  count : Int,
) -> Unit = "wasmoon_jit_ctx_use_shared_table"

///|
/// Configure JIT context with multiple indirect tables (for multi-table support)
/// table_ptrs: FixedArray of Int64 (table pointers from Store.jit_tables)
/// table_sizes: FixedArray of Int (table sizes for bounds checking)
/// table_max_sizes: FixedArray of Int (max sizes, -1 = unlimited)
/// table_count: Number of tables
#borrow(table_ptrs, table_sizes, table_max_sizes)
pub extern "c" fn c_jit_ctx_set_table_pointers(
  ctx_ptr : Int64,
  table_ptrs : FixedArray[Int64],
  table_sizes : FixedArray[Int],
  table_max_sizes : FixedArray[Int],
  table_count : Int,
) -> Unit = "wasmoon_jit_ctx_set_table_pointers"

///|
/// C FFI for trampoline-based calls (new, simple interface)
/// Uses JIT-generated trampoline that handles all ABI complexity
/// trampoline_ptr: Pointer to JIT-generated entry trampoline
/// ctx_ptr: VMContext pointer
/// func_ptr: Target WASM function pointer
/// values_vec: Array of Int64 for args (in) and results (out)
/// values_len: Total number of slots in values_vec
#borrow(values_vec)
pub extern "c" fn c_jit_call_trampoline(
  trampoline_ptr : Int64,
  ctx_ptr : Int64,
  func_ptr : Int64,
  values_vec : FixedArray[Int64],
  values_len : Int,
) -> Int = "wasmoon_jit_call_trampoline"

///|
/// C FFI for trampoline-based calls that keeps the GC-managed `JITContext`
/// alive for the duration of the call.
/// This avoids relying on any global "current context" state.
#borrow(jit_context, values_vec)
pub extern "c" fn c_jit_call_trampoline_managed(
  jit_context : JITContext,
  trampoline_ptr : Int64,
  func_ptr : Int64,
  values_vec : FixedArray[Int64],
  values_len : Int,
) -> Int = "wasmoon_jit_call_trampoline_managed"

// ============ WASM Stack (Independent Stack with Guard Page) ============

///|
/// Allocate an independent WASM stack with guard page protection.
/// The stack is mmap-allocated and has a guard page at the bottom.
/// When the WASM code overflows the stack, it hits the guard page
/// and triggers a controlled "call stack exhausted" trap.
///
/// Parameters:
///   ctx_ptr: JIT context pointer
///   stack_size: Size of the stack in bytes (recommended: 1MB = 1048576)
///
/// Returns: 0 on success, -1 on failure
pub extern "c" fn c_jit_alloc_wasm_stack(
  ctx_ptr : Int64,
  stack_size : Int64,
) -> Int = "wasmoon_jit_alloc_wasm_stack"

///|
/// Get the WASM stack top pointer from a context.
/// Returns 0 if no WASM stack is allocated.
pub extern "c" fn c_jit_get_wasm_stack_top(ctx_ptr : Int64) -> Int64 = "wasmoon_jit_get_wasm_stack_top"

///|
/// Call a WASM function through the trampoline with stack switching.
/// This switches to the independent WASM stack before calling,
/// providing controlled stack overflow behavior.
///
/// If no WASM stack is allocated, falls back to regular call.
#borrow(values_vec)
pub extern "c" fn c_jit_call_with_stack_switch(
  trampoline_ptr : Int64,
  ctx_ptr : Int64,
  func_ptr : Int64,
  values_vec : FixedArray[Int64],
  values_len : Int,
) -> Int = "wasmoon_jit_call_with_stack_switch"

///|
/// GC-managed version of stack-switching call.
#borrow(jit_context, values_vec)
pub extern "c" fn c_jit_call_with_stack_switch_managed(
  jit_context : JITContext,
  trampoline_ptr : Int64,
  func_ptr : Int64,
  values_vec : FixedArray[Int64],
  values_len : Int,
) -> Int = "wasmoon_jit_call_with_stack_switch_managed"

// ============ WASI Trampoline Pointers ============

///|
/// Get fd_write trampoline pointer
pub extern "c" fn c_jit_get_fd_write_ptr() -> Int64 = "wasmoon_jit_get_fd_write_ptr"

///|
/// Get proc_exit trampoline pointer
pub extern "c" fn c_jit_get_proc_exit_ptr() -> Int64 = "wasmoon_jit_get_proc_exit_ptr"

///|
/// Get fd_read trampoline pointer
pub extern "c" fn c_jit_get_fd_read_ptr() -> Int64 = "wasmoon_jit_get_fd_read_ptr"

///|
/// Get args_sizes_get trampoline pointer
pub extern "c" fn c_jit_get_args_sizes_get_ptr() -> Int64 = "wasmoon_jit_get_args_sizes_get_ptr"

///|
/// Get args_get trampoline pointer
pub extern "c" fn c_jit_get_args_get_ptr() -> Int64 = "wasmoon_jit_get_args_get_ptr"

///|
/// Get environ_sizes_get trampoline pointer
pub extern "c" fn c_jit_get_environ_sizes_get_ptr() -> Int64 = "wasmoon_jit_get_environ_sizes_get_ptr"

///|
/// Get environ_get trampoline pointer
pub extern "c" fn c_jit_get_environ_get_ptr() -> Int64 = "wasmoon_jit_get_environ_get_ptr"

///|
/// Get clock_time_get trampoline pointer
pub extern "c" fn c_jit_get_clock_time_get_ptr() -> Int64 = "wasmoon_jit_get_clock_time_get_ptr"

///|
/// Get random_get trampoline pointer
pub extern "c" fn c_jit_get_random_get_ptr() -> Int64 = "wasmoon_jit_get_random_get_ptr"

///|
/// Get fd_close trampoline pointer
pub extern "c" fn c_jit_get_fd_close_ptr() -> Int64 = "wasmoon_jit_get_fd_close_ptr"

///|
/// Get fd_fdstat_get trampoline pointer
pub extern "c" fn c_jit_get_fd_fdstat_get_ptr() -> Int64 = "wasmoon_jit_get_fd_fdstat_get_ptr"

///|
/// Get fd_prestat_get trampoline pointer
pub extern "c" fn c_jit_get_fd_prestat_get_ptr() -> Int64 = "wasmoon_jit_get_fd_prestat_get_ptr"

///|
/// Get fd_prestat_dir_name trampoline pointer
pub extern "c" fn c_jit_get_fd_prestat_dir_name_ptr() -> Int64 = "wasmoon_jit_get_fd_prestat_dir_name_ptr"

///|
/// Get fd_seek trampoline pointer
pub extern "c" fn c_jit_get_fd_seek_ptr() -> Int64 = "wasmoon_jit_get_fd_seek_ptr"

///|
/// Get fd_tell trampoline pointer
pub extern "c" fn c_jit_get_fd_tell_ptr() -> Int64 = "wasmoon_jit_get_fd_tell_ptr"

///|
/// Get fd_sync trampoline pointer
pub extern "c" fn c_jit_get_fd_sync_ptr() -> Int64 = "wasmoon_jit_get_fd_sync_ptr"

///|
/// Get fd_datasync trampoline pointer
pub extern "c" fn c_jit_get_fd_datasync_ptr() -> Int64 = "wasmoon_jit_get_fd_datasync_ptr"

///|
/// Get fd_filestat_get trampoline pointer
pub extern "c" fn c_jit_get_fd_filestat_get_ptr() -> Int64 = "wasmoon_jit_get_fd_filestat_get_ptr"

///|
/// Get fd_filestat_set_size trampoline pointer
pub extern "c" fn c_jit_get_fd_filestat_set_size_ptr() -> Int64 = "wasmoon_jit_get_fd_filestat_set_size_ptr"

///|
/// Get path_open trampoline pointer
pub extern "c" fn c_jit_get_path_open_ptr() -> Int64 = "wasmoon_jit_get_path_open_ptr"

///|
/// Get path_create_directory trampoline pointer
pub extern "c" fn c_jit_get_path_create_directory_ptr() -> Int64 = "wasmoon_jit_get_path_create_directory_ptr"

///|
/// Get path_unlink_file trampoline pointer
pub extern "c" fn c_jit_get_path_unlink_file_ptr() -> Int64 = "wasmoon_jit_get_path_unlink_file_ptr"

///|
/// Get path_remove_directory trampoline pointer
pub extern "c" fn c_jit_get_path_remove_directory_ptr() -> Int64 = "wasmoon_jit_get_path_remove_directory_ptr"

///|
/// Get path_rename trampoline pointer
pub extern "c" fn c_jit_get_path_rename_ptr() -> Int64 = "wasmoon_jit_get_path_rename_ptr"

///|
/// Get clock_res_get trampoline pointer
pub extern "c" fn c_jit_get_clock_res_get_ptr() -> Int64 = "wasmoon_jit_get_clock_res_get_ptr"

///|
/// Get sched_yield trampoline pointer
pub extern "c" fn c_jit_get_sched_yield_ptr() -> Int64 = "wasmoon_jit_get_sched_yield_ptr"

///|
/// Get proc_raise trampoline pointer
pub extern "c" fn c_jit_get_proc_raise_ptr() -> Int64 = "wasmoon_jit_get_proc_raise_ptr"

///|
/// Get poll_oneoff trampoline pointer
pub extern "c" fn c_jit_get_poll_oneoff_ptr() -> Int64 = "wasmoon_jit_get_poll_oneoff_ptr"

///|
/// Get fd_advise trampoline pointer (stub)
pub extern "c" fn c_jit_get_fd_advise_ptr() -> Int64 = "wasmoon_jit_get_fd_advise_ptr"

///|
/// Get fd_allocate trampoline pointer (stub)
pub extern "c" fn c_jit_get_fd_allocate_ptr() -> Int64 = "wasmoon_jit_get_fd_allocate_ptr"

///|
/// Get fd_pread trampoline pointer (stub)
pub extern "c" fn c_jit_get_fd_pread_ptr() -> Int64 = "wasmoon_jit_get_fd_pread_ptr"

///|
/// Get fd_pwrite trampoline pointer (stub)
pub extern "c" fn c_jit_get_fd_pwrite_ptr() -> Int64 = "wasmoon_jit_get_fd_pwrite_ptr"

///|
/// Get fd_readdir trampoline pointer (stub)
pub extern "c" fn c_jit_get_fd_readdir_ptr() -> Int64 = "wasmoon_jit_get_fd_readdir_ptr"

///|
/// Get fd_renumber trampoline pointer (stub)
pub extern "c" fn c_jit_get_fd_renumber_ptr() -> Int64 = "wasmoon_jit_get_fd_renumber_ptr"

///|
/// Get fd_fdstat_set_flags trampoline pointer (stub)
pub extern "c" fn c_jit_get_fd_fdstat_set_flags_ptr() -> Int64 = "wasmoon_jit_get_fd_fdstat_set_flags_ptr"

///|
/// Get fd_fdstat_set_rights trampoline pointer (stub)
pub extern "c" fn c_jit_get_fd_fdstat_set_rights_ptr() -> Int64 = "wasmoon_jit_get_fd_fdstat_set_rights_ptr"

///|
/// Get fd_filestat_set_times trampoline pointer (stub)
pub extern "c" fn c_jit_get_fd_filestat_set_times_ptr() -> Int64 = "wasmoon_jit_get_fd_filestat_set_times_ptr"

///|
/// Get path_filestat_get trampoline pointer (stub)
pub extern "c" fn c_jit_get_path_filestat_get_ptr() -> Int64 = "wasmoon_jit_get_path_filestat_get_ptr"

///|
/// Get path_filestat_set_times trampoline pointer (stub)
pub extern "c" fn c_jit_get_path_filestat_set_times_ptr() -> Int64 = "wasmoon_jit_get_path_filestat_set_times_ptr"

///|
/// Get path_link trampoline pointer (stub)
pub extern "c" fn c_jit_get_path_link_ptr() -> Int64 = "wasmoon_jit_get_path_link_ptr"

///|
/// Get path_readlink trampoline pointer (stub)
pub extern "c" fn c_jit_get_path_readlink_ptr() -> Int64 = "wasmoon_jit_get_path_readlink_ptr"

///|
/// Get path_symlink trampoline pointer (stub)
pub extern "c" fn c_jit_get_path_symlink_ptr() -> Int64 = "wasmoon_jit_get_path_symlink_ptr"

///|
/// Get sock_accept trampoline pointer (stub - returns ENOTSUP)
pub extern "c" fn c_jit_get_sock_accept_ptr() -> Int64 = "wasmoon_jit_get_sock_accept_ptr"

///|
/// Get sock_recv trampoline pointer (stub - returns ENOTSUP)
pub extern "c" fn c_jit_get_sock_recv_ptr() -> Int64 = "wasmoon_jit_get_sock_recv_ptr"

///|
/// Get sock_send trampoline pointer (stub - returns ENOTSUP)
pub extern "c" fn c_jit_get_sock_send_ptr() -> Int64 = "wasmoon_jit_get_sock_send_ptr"

///|
/// Get sock_shutdown trampoline pointer (stub - returns ENOTSUP)
pub extern "c" fn c_jit_get_sock_shutdown_ptr() -> Int64 = "wasmoon_jit_get_sock_shutdown_ptr"

// ============ WASI Context Initialization ============

///|
/// Initialize WASI fd table and preopens
pub extern "c" fn c_jit_init_wasi_fds(
  ctx_ptr : Int64,
  preopen_count : Int,
) -> Unit = "wasmoon_jit_init_wasi_fds"

///|
/// Initialize WASI fd table with stdout/stderr redirected to /dev/null (for testing)
pub extern "c" fn c_jit_init_wasi_fds_quiet(
  ctx_ptr : Int64,
  preopen_count : Int,
) -> Unit = "wasmoon_jit_init_wasi_fds_quiet"

///|
/// Add a preopened directory
#borrow(host_path, guest_path)
pub extern "c" fn c_jit_add_preopen(
  ctx_ptr : Int64,
  idx : Int,
  host_path : FixedArray[Byte],
  guest_path : FixedArray[Byte],
) -> Unit = "wasmoon_jit_add_preopen"

///|
/// Enable or disable stdout capture for WASI
pub extern "c" fn c_jit_set_wasi_stdout_capture(
  ctx_ptr : Int64,
  enabled : Int,
) -> Unit = "wasmoon_jit_set_wasi_stdout_capture"

///|
/// Enable or disable stderr capture for WASI
pub extern "c" fn c_jit_set_wasi_stderr_capture(
  ctx_ptr : Int64,
  enabled : Int,
) -> Unit = "wasmoon_jit_set_wasi_stderr_capture"

///|
/// Set stdin buffer for WASI (custom stdin)
#borrow(data)
pub extern "c" fn c_jit_set_wasi_stdin_buffer(
  ctx_ptr : Int64,
  data : Bytes,
  len : Int,
) -> Unit = "wasmoon_jit_set_wasi_stdin_buffer"

///|
/// Set stdin callback for WASI (custom stdin)
#owned(closure)
pub extern "c" fn c_jit_set_wasi_stdin_callback(
  ctx_ptr : Int64,
  call_closure : FuncRef[(() -> Bytes) -> Bytes],
  closure : () -> Bytes,
) -> Unit = "wasmoon_jit_set_wasi_stdin_callback"

///|
/// Clear stdin callback for WASI
pub extern "c" fn c_jit_clear_wasi_stdin_callback(ctx_ptr : Int64) -> Unit = "wasmoon_jit_clear_wasi_stdin_callback"

///|
/// Clear stdin buffer for WASI
pub extern "c" fn c_jit_clear_wasi_stdin_buffer(ctx_ptr : Int64) -> Unit = "wasmoon_jit_clear_wasi_stdin_buffer"

///|
/// Take captured stdout bytes
pub extern "c" fn c_jit_take_wasi_stdout(ctx_ptr : Int64) -> Bytes = "wasmoon_jit_take_wasi_stdout"

///|
/// Take captured stderr bytes
pub extern "c" fn c_jit_take_wasi_stderr(ctx_ptr : Int64) -> Bytes = "wasmoon_jit_take_wasi_stderr"

///|
/// Free WASI resources
pub extern "c" fn c_jit_free_wasi_fds(ctx_ptr : Int64) -> Unit = "wasmoon_jit_free_wasi_fds"

///|
/// Initialize args array
pub extern "c" fn c_jit_set_wasi_args(ctx_ptr : Int64, argc : Int) -> Unit = "wasmoon_jit_set_wasi_args"

///|
/// Set a single arg
#borrow(arg)
pub extern "c" fn c_jit_set_wasi_arg(
  ctx_ptr : Int64,
  idx : Int,
  arg : FixedArray[Byte],
) -> Unit = "wasmoon_jit_set_wasi_arg"

///|
/// Initialize env array
pub extern "c" fn c_jit_set_wasi_envs(ctx_ptr : Int64, envc : Int) -> Unit = "wasmoon_jit_set_wasi_envs"

///|
/// Set a single env variable
#borrow(env)
pub extern "c" fn c_jit_set_wasi_env(
  ctx_ptr : Int64,
  idx : Int,
  env : FixedArray[Byte],
) -> Unit = "wasmoon_jit_set_wasi_env"

///|
/// Get WASI exit code from context (-1 if none)
pub extern "c" fn c_jit_get_wasi_exit_code(ctx_ptr : Int64) -> Int = "wasmoon_jit_get_wasi_exit_code"

///|
/// Clear WASI exit state in context
pub extern "c" fn c_jit_clear_wasi_exit(ctx_ptr : Int64) -> Unit = "wasmoon_jit_clear_wasi_exit"

// ============ Spectest Trampolines ============

///|
/// Get spectest print trampoline pointer
pub extern "c" fn c_jit_get_spectest_print_ptr() -> Int64 = "wasmoon_jit_get_spectest_print_ptr"

///|
/// Get spectest print_i32 trampoline pointer
pub extern "c" fn c_jit_get_spectest_print_i32_ptr() -> Int64 = "wasmoon_jit_get_spectest_print_i32_ptr"

///|
/// Get spectest print_i64 trampoline pointer
pub extern "c" fn c_jit_get_spectest_print_i64_ptr() -> Int64 = "wasmoon_jit_get_spectest_print_i64_ptr"

///|
/// Get spectest print_f32 trampoline pointer
pub extern "c" fn c_jit_get_spectest_print_f32_ptr() -> Int64 = "wasmoon_jit_get_spectest_print_f32_ptr"

///|
/// Get spectest print_f64 trampoline pointer
pub extern "c" fn c_jit_get_spectest_print_f64_ptr() -> Int64 = "wasmoon_jit_get_spectest_print_f64_ptr"

///|
/// Get spectest print_i32_f32 trampoline pointer
pub extern "c" fn c_jit_get_spectest_print_i32_f32_ptr() -> Int64 = "wasmoon_jit_get_spectest_print_i32_f32_ptr"

///|
/// Get spectest print_f64_f64 trampoline pointer
pub extern "c" fn c_jit_get_spectest_print_f64_f64_ptr() -> Int64 = "wasmoon_jit_get_spectest_print_f64_f64_ptr"

///|
/// Get spectest print_char trampoline pointer
pub extern "c" fn c_jit_get_spectest_print_char_ptr() -> Int64 = "wasmoon_jit_get_spectest_print_char_ptr"

// ============ Bulk Memory Operations ============

///|
/// memory.fill: Fill memory region with a byte value
/// Parameters: dst (offset), val (byte value), size (count)
/// Traps if out of bounds
pub extern "c" fn c_jit_memory_fill(dst : Int, val : Int, size : Int) -> Unit = "wasmoon_jit_memory_fill"

///|
/// memory.copy: Copy memory region
/// Parameters: dst (dest offset), src (source offset), size (count)
/// Handles overlapping regions correctly
/// Traps if out of bounds
pub extern "c" fn c_jit_memory_copy(dst : Int, src : Int, size : Int) -> Unit = "wasmoon_jit_memory_copy"

// ============ Executable Memory Management ============

///|
/// Allocate executable memory
/// Returns pointer as Int64 (0 on failure)
pub extern "c" fn c_jit_alloc_exec(size : Int) -> Int64 = "wasmoon_jit_alloc_exec"

///|
/// Copy code to executable memory
/// Returns 0 on success, -1 on failure
#borrow(src)
pub extern "c" fn c_jit_copy_code(
  dest : Int64,
  src : FixedArray[Byte],
  size : Int,
) -> Int = "wasmoon_jit_copy_code"

// ============ GC-managed ExecCode ============

///|
/// GC-managed executable code object
/// The memory is automatically freed when the object is garbage collected
pub type ExecCode

///|
/// Allocate GC-managed executable code
/// Returns the allocated ExecCode object
#borrow(code)
pub extern "c" fn c_jit_alloc_exec_managed(
  code : FixedArray[Byte],
  size : Int,
) -> ExecCode = "wasmoon_jit_alloc_exec_managed"

///|
/// Get the function pointer from a GC-managed ExecCode object
#owned(exec_code)
pub extern "c" fn c_jit_exec_code_ptr(exec_code : ExecCode) -> Int64 = "wasmoon_jit_exec_code_ptr"

// ============ Multi-value Return Support ============

///|
/// C FFI for multi-value return calls
/// result_types uses: 0=I32, 1=I64, 2=F32, 3=F64
#borrow(args, results, result_types)
pub extern "c" fn c_jit_call_multi_return(
  func_ptr : Int64,
  func_table_ptr : Int64,
  args : FixedArray[Int64],
  num_args : Int,
  results : FixedArray[Int64],
  result_types : FixedArray[Int],
  num_results : Int,
) -> Int = "wasmoon_jit_call_multi_return"

///|
/// Write an int64 value to a memory address
pub extern "c" fn c_jit_write_i64(addr : Int64, value : Int64) -> Unit = "wasmoon_jit_write_i64"

///|
/// Write a u32 value to a memory address
pub extern "c" fn c_jit_write_u32(addr : Int64, value : Int) -> Unit = "wasmoon_jit_write_u32"

///|
/// Read an int64 value from a memory address
pub extern "c" fn c_jit_read_i64(addr : Int64) -> Int64 = "wasmoon_jit_read_i64"

// ============ GC Runtime Helpers ============

///|
/// Get ref.test libcall function pointer
pub extern "c" fn c_jit_get_gc_ref_test_ptr() -> Int64 = "wasmoon_jit_get_gc_ref_test_ptr"

///|
/// Get ref.cast libcall function pointer
pub extern "c" fn c_jit_get_gc_ref_cast_ptr() -> Int64 = "wasmoon_jit_get_gc_ref_cast_ptr"

///|
/// Get struct.new libcall function pointer
pub extern "c" fn c_jit_get_gc_struct_new_ptr() -> Int64 = "wasmoon_jit_get_gc_struct_new_ptr"

///|
/// Get struct.get libcall function pointer
pub extern "c" fn c_jit_get_gc_struct_get_ptr() -> Int64 = "wasmoon_jit_get_gc_struct_get_ptr"

///|
/// Get struct.set libcall function pointer
pub extern "c" fn c_jit_get_gc_struct_set_ptr() -> Int64 = "wasmoon_jit_get_gc_struct_set_ptr"

///|
/// Get array.new libcall function pointer
pub extern "c" fn c_jit_get_gc_array_new_ptr() -> Int64 = "wasmoon_jit_get_gc_array_new_ptr"

///|
/// Get array.get libcall function pointer
pub extern "c" fn c_jit_get_gc_array_get_ptr() -> Int64 = "wasmoon_jit_get_gc_array_get_ptr"

///|
/// Get array.set libcall function pointer
pub extern "c" fn c_jit_get_gc_array_set_ptr() -> Int64 = "wasmoon_jit_get_gc_array_set_ptr"

///|
/// Get array.len libcall function pointer
pub extern "c" fn c_jit_get_gc_array_len_ptr() -> Int64 = "wasmoon_jit_get_gc_array_len_ptr"

///|
/// Get array.fill libcall function pointer
/// Signature: void gc_array_fill(int64_t ref, int32_t offset, int64_t value, int32_t count)
pub extern "c" fn c_jit_get_gc_array_fill_ptr() -> Int64 = "wasmoon_jit_get_gc_array_fill_ptr"

///|
/// Get array.copy libcall function pointer
/// Signature: void gc_array_copy(int64_t dst_ref, int32_t dst_offset, int64_t src_ref, int32_t src_offset, int32_t count)
pub extern "c" fn c_jit_get_gc_array_copy_ptr() -> Int64 = "wasmoon_jit_get_gc_array_copy_ptr"

///|
/// Get array.new_data libcall function pointer
/// Signature: int64_t gc_array_new_data(ctx, type_idx, data_idx, data_offset, length) -> arrayref
pub extern "c" fn c_jit_get_gc_array_new_data_ptr() -> Int64 = "wasmoon_jit_get_gc_array_new_data_ptr"

///|
/// Get array.new_elem libcall function pointer
/// Signature: int64_t gc_array_new_elem(ctx, type_idx, elem_idx, elem_offset, length) -> arrayref
pub extern "c" fn c_jit_get_gc_array_new_elem_ptr() -> Int64 = "wasmoon_jit_get_gc_array_new_elem_ptr"

///|
/// Get array.init_data libcall function pointer
/// Signature: void gc_array_init_data(ctx, type_idx, data_idx, arrayref, arr_offset, data_offset, length)
pub extern "c" fn c_jit_get_gc_array_init_data_ptr() -> Int64 = "wasmoon_jit_get_gc_array_init_data_ptr"

///|
/// Get array.init_elem libcall function pointer
/// Signature: void gc_array_init_elem(ctx, type_idx, elem_idx, arrayref, arr_offset, elem_offset, length)
pub extern "c" fn c_jit_get_gc_array_init_elem_ptr() -> Int64 = "wasmoon_jit_get_gc_array_init_elem_ptr"

///|
/// Get type check subtype libcall function pointer for call_indirect with subtyping
/// Signature: void gc_type_check_subtype(int32_t actual_type, int32_t expected_type)
/// Traps if actual_type is not a subtype of expected_type
pub extern "c" fn c_jit_get_gc_type_check_subtype_ptr() -> Int64 = "wasmoon_jit_get_gc_type_check_subtype_ptr"

///|
/// Get gc_register_struct_inline function pointer for inline allocation
/// Signature: int64_t gc_register_struct_inline(jit_context_t *ctx, uint8_t *obj_ptr, int32_t total_size)
pub extern "c" fn c_jit_get_gc_register_struct_inline_ptr() -> Int64 = "wasmoon_jit_get_gc_register_struct_inline_ptr"

///|
/// Get gc_register_array_inline function pointer for inline allocation
/// Signature: int64_t gc_register_array_inline(jit_context_t *ctx, uint8_t *obj_ptr, int32_t total_size)
pub extern "c" fn c_jit_get_gc_register_array_inline_ptr() -> Int64 = "wasmoon_jit_get_gc_register_array_inline_ptr"

///|
/// Get gc_alloc_struct_slow function pointer for slow path
/// Signature: int64_t gc_alloc_struct_slow(jit_context_t *ctx, int32_t type_idx, int64_t *fields, int32_t num_fields)
pub extern "c" fn c_jit_get_gc_alloc_struct_slow_ptr() -> Int64 = "wasmoon_jit_get_gc_alloc_struct_slow_ptr"

///|
/// Get gc_alloc_array_slow function pointer for slow path
/// Signature: int64_t gc_alloc_array_slow(jit_context_t *ctx, int32_t type_idx, int32_t len, int64_t init_value)
pub extern "c" fn c_jit_get_gc_alloc_array_slow_ptr() -> Int64 = "wasmoon_jit_get_gc_alloc_array_slow_ptr"

///|
/// Set type cache for GC operations
/// types_data: array of [super_idx, kind] pairs per type
#borrow(types_data)
pub extern "c" fn c_jit_gc_set_type_cache(
  types_data : FixedArray[Int],
  num_types : Int,
) -> Unit = "wasmoon_jit_gc_set_type_cache"

///|
/// Set canonical type indices for subtyping
#borrow(canonical)
pub extern "c" fn c_jit_gc_set_canonical_indices(
  canonical : FixedArray[Int],
  num_types : Int,
) -> Unit = "wasmoon_jit_gc_set_canonical_indices"

///|
/// Set function type indices for funcref subtyping
#borrow(func_type_indices)
pub extern "c" fn c_jit_gc_set_func_type_indices(
  func_type_indices : FixedArray[Int],
  num_funcs : Int,
) -> Unit = "wasmoon_jit_gc_set_func_type_indices"

///|
/// Set function table pointer for funcref lookup
pub extern "c" fn c_jit_gc_set_func_table(
  func_table_ptr : Int64,
  num_funcs : Int,
) -> Unit = "wasmoon_jit_gc_set_func_table"

///|
/// Clear GC cache after JIT execution
pub extern "c" fn c_jit_gc_clear_cache() -> Unit = "wasmoon_jit_gc_clear_cache"

///|
/// Set GC heap pointer for JIT execution
pub extern "c" fn c_jit_gc_set_heap(heap_ptr : Int64) -> Unit = "wasmoon_jit_gc_set_heap"

///|
/// Clear GC heap pointer after JIT execution
pub extern "c" fn c_jit_gc_clear_heap() -> Unit = "wasmoon_jit_gc_clear_heap"

///|
/// Get current GC heap pointer (for debugging)
pub extern "c" fn c_jit_gc_get_heap() -> Int64 = "wasmoon_jit_gc_get_heap"

///|
/// Set GC heap pointer in VMContext for inline allocation
/// This enables ctx-passing GC libcalls
pub extern "c" fn c_jit_ctx_set_gc_heap(
  ctx_ptr : Int64,
  heap_ptr : Int64,
) -> Unit = "wasmoon_jit_ctx_set_gc_heap"

// ============ C GC Heap ============

///|
/// Create a new GC heap with the given initial capacity
/// Returns heap pointer as Int64
pub extern "c" fn c_gc_heap_new(capacity : Int64) -> Int64 = "wasmoon_gc_heap_new"

///|
/// Free a GC heap and all its memory
pub extern "c" fn c_gc_heap_free(heap : Int64) -> Unit = "wasmoon_gc_heap_free"

// ============ Segment Setup (for memory.init/data.drop/table.init/elem.drop) ============

///|
/// Initialize data segment storage with count segments
pub extern "c" fn c_jit_init_data_segments(count : Int) -> Unit = "wasmoon_jit_init_data_segments"

///|
/// Add a single data segment - C takes ownership (no copy, uses pointer directly)
/// idx: segment index, data: FixedArray[Byte] (ownership transferred to C)
/// C will call moonbit_decref when clearing segments
#owned(data)
pub extern "c" fn c_jit_add_data_segment(
  idx : Int,
  data : FixedArray[Byte],
  size : Int,
) -> Unit = "wasmoon_jit_add_data_segment"

///|
/// Initialize element segment storage with count segments
pub extern "c" fn c_jit_init_elem_segments(count : Int) -> Unit = "wasmoon_jit_init_elem_segments"

///|
/// Add a single element segment - C takes ownership (no copy, uses pointer directly)
/// idx: segment index, data: FixedArray[Int64] (ownership transferred to C)
/// C will call moonbit_decref when clearing segments
#owned(data)
pub extern "c" fn c_jit_add_elem_segment(
  idx : Int,
  data : FixedArray[Int64],
  size : Int,
) -> Unit = "wasmoon_jit_add_elem_segment"

///|
/// Clear all segment state after JIT execution
pub extern "c" fn c_jit_clear_segments() -> Unit = "wasmoon_jit_clear_segments"

// ============ Struct Operations ============

///|
/// Allocate a new struct
/// Returns gc_ref (1-based index), or 0 on failure
#borrow(fields)
pub extern "c" fn c_gc_heap_alloc_struct(
  heap : Int64,
  type_idx : Int,
  fields : FixedArray[Int64],
  num_fields : Int,
) -> Int = "wasmoon_gc_heap_alloc_struct"

///|
/// Get a struct field value
pub extern "c" fn c_gc_heap_struct_get(
  heap : Int64,
  gc_ref : Int,
  field_idx : Int,
) -> Int64 = "wasmoon_gc_heap_struct_get"

///|
/// Set a struct field value
pub extern "c" fn c_gc_heap_struct_set(
  heap : Int64,
  gc_ref : Int,
  field_idx : Int,
  value : Int64,
) -> Unit = "wasmoon_gc_heap_struct_set"

// ============ Array Operations ============

///|
/// Allocate a new array
/// Returns gc_ref (1-based index), or 0 on failure
pub extern "c" fn c_gc_heap_alloc_array(
  heap : Int64,
  type_idx : Int,
  len : Int,
  init_value : Int64,
) -> Int = "wasmoon_gc_heap_alloc_array"

///|
/// Allocate a new array from existing values
/// Returns gc_ref (1-based index), or 0 on failure
#borrow(values)
pub extern "c" fn c_gc_heap_alloc_array_from_values(
  heap : Int64,
  type_idx : Int,
  values : FixedArray[Int64],
  len : Int,
) -> Int = "wasmoon_gc_heap_alloc_array_from_values"

///|
/// Get array length
pub extern "c" fn c_gc_heap_array_len(heap : Int64, gc_ref : Int) -> Int = "wasmoon_gc_heap_array_len"

///|
/// Get an array element
pub extern "c" fn c_gc_heap_array_get(
  heap : Int64,
  gc_ref : Int,
  idx : Int,
) -> Int64 = "wasmoon_gc_heap_array_get"

///|
/// Set an array element
pub extern "c" fn c_gc_heap_array_set(
  heap : Int64,
  gc_ref : Int,
  idx : Int,
  value : Int64,
) -> Unit = "wasmoon_gc_heap_array_set"

///|
/// Fill array elements with a value
pub extern "c" fn c_gc_heap_array_fill(
  heap : Int64,
  gc_ref : Int,
  offset : Int,
  value : Int64,
  count : Int,
) -> Unit = "wasmoon_gc_heap_array_fill"

///|
/// Copy array elements
pub extern "c" fn c_gc_heap_array_copy(
  heap : Int64,
  dst_ref : Int,
  dst_offset : Int,
  src_ref : Int,
  src_offset : Int,
  count : Int,
) -> Unit = "wasmoon_gc_heap_array_copy"

// ============ Type Information ============

///|
/// Get the type index of an object
pub extern "c" fn c_gc_heap_get_type_idx(heap : Int64, gc_ref : Int) -> Int = "wasmoon_gc_heap_get_type_idx"

///|
/// Get the kind of an object (1=struct, 2=array)
pub extern "c" fn c_gc_heap_get_kind(heap : Int64, gc_ref : Int) -> Int = "wasmoon_gc_heap_get_kind"

///|
/// Check if a gc_ref is valid (non-null and within bounds)
pub extern "c" fn c_gc_heap_is_valid(heap : Int64, gc_ref : Int) -> Int = "wasmoon_gc_heap_is_valid"

// ============ GC Operations ============

///|
/// Mark an object as reachable (for GC)
pub extern "c" fn c_gc_heap_mark(heap : Int64, gc_ref : Int) -> Unit = "wasmoon_gc_heap_mark"

///|
/// Mark all objects reachable from roots
#borrow(roots)
pub extern "c" fn c_gc_heap_mark_roots(
  heap : Int64,
  roots : FixedArray[Int64],
  num_roots : Int,
) -> Unit = "wasmoon_gc_heap_mark_roots"

///|
/// Sweep unmarked objects
/// Returns number of objects collected
pub extern "c" fn c_gc_heap_sweep(heap : Int64) -> Int = "wasmoon_gc_heap_sweep"

///|
/// Perform a full GC cycle (mark + sweep)
/// Returns number of objects collected
#borrow(roots)
pub extern "c" fn c_gc_heap_collect(
  heap : Int64,
  roots : FixedArray[Int64],
  num_roots : Int,
) -> Int = "wasmoon_gc_heap_collect"

// ============ JIT Utilities ============

///|
/// Get heap base pointer (for JIT inline access)
pub extern "c" fn c_gc_heap_get_base(heap : Int64) -> Int64 = "wasmoon_gc_heap_get_base"

///|
/// Get object offset in heap (for JIT inline access)
pub extern "c" fn c_gc_heap_get_offset(heap : Int64, gc_ref : Int) -> Int = "wasmoon_gc_heap_get_offset"

///|
/// Get current heap size (bytes used)
pub extern "c" fn c_gc_heap_get_size(heap : Int64) -> Int64 = "wasmoon_gc_heap_get_size"

///|
/// Get heap capacity (total allocated bytes)
pub extern "c" fn c_gc_heap_get_capacity(heap : Int64) -> Int64 = "wasmoon_gc_heap_get_capacity"

///|
/// Get number of objects in heap
pub extern "c" fn c_gc_heap_get_object_count(heap : Int64) -> Int = "wasmoon_gc_heap_get_object_count"

///|
/// Get total number of allocations since heap creation
pub extern "c" fn c_gc_heap_get_total_allocations(heap : Int64) -> Int = "wasmoon_gc_heap_get_total_allocations"

///|
/// Get total number of GC cycles performed
pub extern "c" fn c_gc_heap_get_total_collections(heap : Int64) -> Int = "wasmoon_gc_heap_get_total_collections"

// ============ Exception Handling ============

///|
/// Get exception try_begin function pointer for JIT
/// Signature: try_begin(ctx: *jit_context_t, handler_id: i32) -> *sigjmp_buf
pub extern "c" fn c_jit_get_exception_try_begin_ptr() -> Int64 = "wasmoon_jit_get_exception_try_begin_ptr"

///|
/// Get exception try_end function pointer for JIT
/// Signature: try_end(ctx: *jit_context_t, handler_id: i32)
pub extern "c" fn c_jit_get_exception_try_end_ptr() -> Int64 = "wasmoon_jit_get_exception_try_end_ptr"

///|
/// Get exception throw function pointer for JIT
/// Signature: throw(ctx: *jit_context_t, tag_addr: i32, values_ptr: i64, count: i32) -> noreturn
pub extern "c" fn c_jit_get_exception_throw_ptr() -> Int64 = "wasmoon_jit_get_exception_throw_ptr"

///|
/// Get exception throw_ref function pointer for JIT
/// Signature: throw_ref(ctx: *jit_context_t, exnref: i64) -> noreturn
pub extern "c" fn c_jit_get_exception_throw_ref_ptr() -> Int64 = "wasmoon_jit_get_exception_throw_ref_ptr"

///|
/// Get exception delegate function pointer for JIT
/// Signature: delegate(ctx: *jit_context_t, depth: i32) -> noreturn
pub extern "c" fn c_jit_get_exception_delegate_ptr() -> Int64 = "wasmoon_jit_get_exception_delegate_ptr"

///|
/// Get exception get_tag function pointer for JIT
/// Signature: get_tag(ctx: *jit_context_t) -> i32
pub extern "c" fn c_jit_get_exception_get_tag_ptr() -> Int64 = "wasmoon_jit_get_exception_get_tag_ptr"

///|
/// Get exception get_value function pointer for JIT
/// Signature: get_value(ctx: *jit_context_t, idx: i32) -> i64
pub extern "c" fn c_jit_get_exception_get_value_ptr() -> Int64 = "wasmoon_jit_get_exception_get_value_ptr"

///|
/// Get exception get_value_count function pointer for JIT
/// Signature: get_value_count(ctx: *jit_context_t) -> i32
pub extern "c" fn c_jit_get_exception_get_value_count_ptr() -> Int64 = "wasmoon_jit_get_exception_get_value_count_ptr"

///|
/// Get sigsetjmp function pointer for JIT to call directly
/// Signature: sigsetjmp(jmp_buf, savemask: i32) -> i32
/// Returns 0 on first call, handler_id on longjmp return
pub extern "c" fn c_jit_get_sigsetjmp_ptr() -> Int64 = "wasmoon_jit_get_sigsetjmp_ptr"

///|
/// Get exception spill_locals function pointer for JIT
/// Signature: spill_locals(ctx: *jit_context_t, locals: *i64, count: i32) -> void
/// Saves locals before throw so catch handlers see throw-time values
pub extern "c" fn c_jit_get_exception_spill_locals_ptr() -> Int64 = "wasmoon_jit_get_exception_spill_locals_ptr"

///|
/// Get exception get_spilled_local function pointer for JIT
/// Signature: get_spilled_local(ctx: *jit_context_t, idx: i32) -> i64
/// Gets a spilled local value for catch handlers
pub extern "c" fn c_jit_get_exception_get_spilled_local_ptr() -> Int64 = "wasmoon_jit_get_exception_get_spilled_local_ptr"

// ============ DWARF Debug Info ============

///|
/// Create a new DWARF debug info builder
/// Returns an opaque handle to pass to other DWARF functions
pub extern "c" fn c_dwarf_create() -> Int64 = "wasmoon_dwarf_create"

///|
/// Add a function to the DWARF debug info
/// Parameters:
///   dwarf: Handle from c_dwarf_create()
///   name: Function name (null-terminated bytes)
///   addr: Function start address
///   size: Function size in bytes
///   func_idx: WebAssembly function index
#borrow(name)
pub extern "c" fn c_dwarf_add_function(
  dwarf : Int64,
  name : Bytes,
  addr : Int64,
  size : Int,
  func_idx : Int,
) -> Unit = "wasmoon_dwarf_add_function"

///|
/// Register the DWARF debug info with the debugger (LLDB/GDB)
/// This generates an in-memory Mach-O/ELF object and registers it
/// via the GDB JIT interface
/// verbose: if true, print debug info to stderr
pub extern "c" fn c_dwarf_register(dwarf : Int64, verbose : Int) -> Unit = "wasmoon_dwarf_register"

///|
/// Unregister DWARF debug info from the debugger
pub extern "c" fn c_dwarf_unregister(dwarf : Int64) -> Unit = "wasmoon_dwarf_unregister"

///|
/// Destroy the DWARF builder and free resources
/// Also unregisters debug info if registered
pub extern "c" fn c_dwarf_destroy(dwarf : Int64) -> Unit = "wasmoon_dwarf_destroy"

///|
/// Set the active DWARF builder for address lookups
/// This is used for backtrace symbolication
pub extern "c" fn c_dwarf_set_active(dwarf : Int64) -> Unit = "wasmoon_dwarf_set_active"

///|
/// Lookup an address in the DWARF debug info
/// Returns 1 if found, 0 if not found
/// If found, writes results to the provided arrays
#borrow(name_out, func_idx_out, offset_out)
pub extern "c" fn c_dwarf_lookup_address(
  dwarf : Int64,
  addr : Int64,
  name_out : FixedArray[Byte],
  name_size : Int,
  func_idx_out : FixedArray[Int],
  offset_out : FixedArray[Int64],
) -> Int = "wasmoon_dwarf_lookup_address"

///|
/// Capture a backtrace starting from the given PC and FP
/// Returns the number of frames captured
/// frames_out contains alternating (pc, fp) pairs
#borrow(frames_out)
pub extern "c" fn c_dwarf_capture_backtrace(
  initial_pc : Int64,
  initial_fp : Int64,
  frames_out : FixedArray[Int64],
  max_frames : Int,
) -> Int = "wasmoon_dwarf_capture_backtrace"

///|
/// Capture a backtrace with LR fallback (for when FP is 0)
/// Returns the number of frames captured
/// frames_out contains alternating (pc, fp) pairs
#borrow(frames_out)
pub extern "c" fn c_dwarf_capture_backtrace_ex(
  initial_pc : Int64,
  initial_fp : Int64,
  initial_lr : Int64,
  frames_out : FixedArray[Int64],
  max_frames : Int,
) -> Int = "wasmoon_dwarf_capture_backtrace_ex"

///|
/// Format a backtrace as a string
/// Returns the number of bytes written (excluding null terminator)
#borrow(frames, buffer)
pub extern "c" fn c_dwarf_format_backtrace(
  dwarf : Int64,
  frames : FixedArray[Int64],
  frame_count : Int,
  buffer : FixedArray[Byte],
  buffer_size : Int,
) -> Int = "wasmoon_dwarf_format_backtrace"
