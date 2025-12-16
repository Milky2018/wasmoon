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
/// Set memory in the context
pub extern "c" fn c_jit_ctx_set_memory(
  ctx_ptr : Int64,
  mem_ptr : Int64,
  mem_size : Int64,
) -> Unit = "wasmoon_jit_ctx_set_memory"

///|
/// Get memory base from context
pub extern "c" fn c_jit_ctx_get_memory(ctx_ptr : Int64) -> Int64 = "wasmoon_jit_ctx_get_memory"

///|
/// Allocate linear memory for WASM
pub extern "c" fn c_jit_alloc_memory(size : Int64) -> Int64 = "wasmoon_jit_alloc_memory"

///|
/// Free linear memory
pub extern "c" fn c_jit_free_memory(mem_ptr : Int64) -> Unit = "wasmoon_jit_free_memory"

///|
/// Get memory_grow v2 function pointer for JIT
pub extern "c" fn c_jit_get_memory_grow_ptr() -> Int64 = "wasmoon_jit_get_memory_grow_ptr"

///|
/// Get get_memory_base v2 function pointer for JIT
pub extern "c" fn c_jit_get_memory_base_ptr() -> Int64 = "wasmoon_jit_get_memory_base_ptr"

///|
/// Get get_memory_size_bytes v2 function pointer for JIT
pub extern "c" fn c_jit_get_memory_size_bytes_ptr() -> Int64 = "wasmoon_jit_get_memory_size_bytes_ptr"

///|
/// Get memory_size v2 function pointer for JIT (returns pages)
pub extern "c" fn c_jit_get_memory_size_ptr() -> Int64 = "wasmoon_jit_get_memory_size_ptr"

///|
/// Get memory_fill v2 function pointer for JIT
pub extern "c" fn c_jit_get_memory_fill_ptr() -> Int64 = "wasmoon_jit_get_memory_fill_ptr"

///|
/// Get memory_copy v2 function pointer for JIT
pub extern "c" fn c_jit_get_memory_copy_ptr() -> Int64 = "wasmoon_jit_get_memory_copy_ptr"

///|
/// Get current memory base from v2 context (for proper cleanup after memory.grow)
pub extern "c" fn c_jit_get_current_memory_base() -> Int64 = "wasmoon_jit_get_memory_base"

///|
/// Set globals array in the context v2
pub extern "c" fn c_jit_ctx_set_globals(
  ctx_ptr : Int64,
  globals_ptr : Int64,
) -> Unit = "wasmoon_jit_ctx_set_globals"

///|
/// Get function table base address from context v2
pub extern "c" fn c_jit_ctx_get_func_table(ctx_ptr : Int64) -> Int64 = "wasmoon_jit_ctx_get_func_table"

///|
/// Allocate indirect table for context v2
pub extern "c" fn c_jit_ctx_alloc_indirect_table(
  ctx_ptr : Int64,
  count : Int,
) -> Int = "wasmoon_jit_ctx_alloc_indirect_table"

///|
/// Set an entry in indirect table v2 (table_idx -> func_table[func_idx])
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
/// table_count: Number of tables
#borrow(table_ptrs)
pub extern "c" fn c_jit_ctx_set_table_pointers(
  ctx_ptr : Int64,
  table_ptrs : FixedArray[Int64],
  table_count : Int,
) -> Unit = "wasmoon_jit_ctx_set_table_pointers"

///|
/// Set the global JIT context v2 with managed object (handles reference counting)
/// This prevents GC from collecting the context while it's active
#borrow(jit_context)
pub extern "c" fn c_jit_set_context_managed(jit_context : JITContext) -> Unit = "wasmoon_jit_set_context_managed"

///|
/// C FFI for v2 ABI multi-value return calls
/// X19 = context pointer, X0-X7 = int params, D0-D7 = float params
/// param_types and result_types use: 0=I32, 1=I64, 2=F32, 3=F64
#borrow(args, param_types, results, result_types)
pub extern "c" fn c_jit_call(
  ctx_ptr : Int64,
  func_ptr : Int64,
  args : FixedArray[Int64],
  param_types : FixedArray[Int],
  num_args : Int,
  results : FixedArray[Int64],
  result_types : FixedArray[Int],
  num_results : Int,
) -> Int = "wasmoon_jit_call"

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

///|
/// Free executable memory
/// Returns 0 on success, -1 on failure
pub extern "c" fn c_jit_free_exec(ptr : Int64) -> Int = "wasmoon_jit_free_exec"

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
