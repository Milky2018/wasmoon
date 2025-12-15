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

// ============ JIT Context Management ============

///|
/// Allocate a JIT context with function table
pub extern "c" fn c_jit_alloc_context(func_count : Int) -> Int64 = "wasmoon_jit_alloc_context"

///|
/// Free a JIT context
pub extern "c" fn c_jit_free_context(ctx_ptr : Int64) -> Unit = "wasmoon_jit_free_context"

///|
/// Set a function pointer in the context's function table
pub extern "c" fn c_jit_ctx_set_func(
  ctx_ptr : Int64,
  idx : Int,
  func_ptr : Int64,
) -> Unit = "wasmoon_jit_ctx_set_func"

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
/// Copy data to linear memory at offset
#borrow(data)
pub extern "c" fn c_jit_memory_init(
  mem_ptr : Int64,
  offset : Int64,
  data : FixedArray[Byte],
  size : Int,
) -> Int = "wasmoon_jit_memory_init"

// ============ Memory Grow Support ============

///|
/// Get memory_grow function pointer for JIT
pub extern "c" fn c_jit_get_memory_grow_ptr() -> Int64 = "wasmoon_jit_get_memory_grow_ptr"

///|
/// Get get_memory_base function pointer for JIT
pub extern "c" fn c_jit_get_memory_base_ptr() -> Int64 = "wasmoon_jit_get_memory_base_ptr"

///|
/// Get get_memory_size_bytes function pointer for JIT
pub extern "c" fn c_jit_get_memory_size_bytes_ptr() -> Int64 = "wasmoon_jit_get_memory_size_bytes_ptr"

///|
/// Get memory_size function pointer for JIT (returns pages)
pub extern "c" fn c_jit_get_memory_size_ptr() -> Int64 = "wasmoon_jit_get_memory_size_ptr"

// ============ Memory v2 functions (for v2 ABI) ============

///|
/// Get memory_grow v2 function pointer for JIT
pub extern "c" fn c_jit_get_memory_grow_v2_ptr() -> Int64 = "wasmoon_jit_get_memory_grow_v2_ptr"

///|
/// Get get_memory_base v2 function pointer for JIT
pub extern "c" fn c_jit_get_memory_base_v2_ptr() -> Int64 = "wasmoon_jit_get_memory_base_v2_ptr"

///|
/// Get get_memory_size_bytes v2 function pointer for JIT
pub extern "c" fn c_jit_get_memory_size_bytes_v2_ptr() -> Int64 = "wasmoon_jit_get_memory_size_bytes_v2_ptr"

///|
/// Get memory_size v2 function pointer for JIT (returns pages)
pub extern "c" fn c_jit_get_memory_size_v2_ptr() -> Int64 = "wasmoon_jit_get_memory_size_v2_ptr"

///|
/// Get current memory base from v2 context (for proper cleanup after memory.grow)
pub extern "c" fn c_jit_get_current_memory_base_v2() -> Int64 = "wasmoon_jit_get_memory_base_v2"

///|
/// Get function table base address from context
pub extern "c" fn c_jit_ctx_get_func_table(ctx_ptr : Int64) -> Int64 = "wasmoon_jit_ctx_get_func_table"

///|
/// Allocate indirect table for call_indirect
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

///|
/// Set the global JIT context (for WASI trampolines)
pub extern "c" fn c_jit_set_context(ctx_ptr : Int64) -> Unit = "wasmoon_jit_set_context"

// ============ JIT Context v2 Management ============
// v2 context has fixed field offsets for JIT prologue:
// +0: func_table, +8: indirect_table, +16: memory_base, +24: memory_size

///|
/// Allocate a JIT context v2 with function table
pub extern "c" fn c_jit_alloc_context_v2(func_count : Int) -> Int64 = "wasmoon_jit_alloc_context_v2"

///|
/// Free a JIT context v2
pub extern "c" fn c_jit_free_context_v2(ctx_ptr : Int64) -> Unit = "wasmoon_jit_free_context_v2"

///|
/// Set a function pointer in the context v2's function table
pub extern "c" fn c_jit_ctx_v2_set_func(
  ctx_ptr : Int64,
  idx : Int,
  func_ptr : Int64,
) -> Unit = "wasmoon_jit_ctx_v2_set_func"

///|
/// Set memory in the context v2
pub extern "c" fn c_jit_ctx_v2_set_memory(
  ctx_ptr : Int64,
  mem_ptr : Int64,
  mem_size : Int64,
) -> Unit = "wasmoon_jit_ctx_v2_set_memory"

///|
/// Get function table base address from context v2
pub extern "c" fn c_jit_ctx_v2_get_func_table(ctx_ptr : Int64) -> Int64 = "wasmoon_jit_ctx_v2_get_func_table"

///|
/// Allocate indirect table for context v2
pub extern "c" fn c_jit_ctx_v2_alloc_indirect_table(
  ctx_ptr : Int64,
  count : Int,
) -> Int = "wasmoon_jit_ctx_v2_alloc_indirect_table"

///|
/// Set an entry in indirect table v2 (table_idx -> func_table[func_idx])
/// type_idx: the type index of the function (for type checking)
pub extern "c" fn c_jit_ctx_v2_set_indirect(
  ctx_ptr : Int64,
  table_idx : Int,
  func_idx : Int,
  type_idx : Int,
) -> Unit = "wasmoon_jit_ctx_v2_set_indirect"

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
pub extern "c" fn c_jit_ctx_v2_use_shared_table(
  ctx_ptr : Int64,
  shared_table_ptr : Int64,
  count : Int,
) -> Unit = "wasmoon_jit_ctx_v2_use_shared_table"

///|
/// Set the global JIT context v2 (for WASI trampolines)
pub extern "c" fn c_jit_set_context_v2(ctx_ptr : Int64) -> Unit = "wasmoon_jit_set_context_v2"

///|
/// C FFI for v2 ABI multi-value return calls
/// X19 = context pointer, X0-X7 = int params, D0-D7 = float params
/// param_types and result_types use: 0=I32, 1=I64, 2=F32, 3=F64
#borrow(args, param_types, results, result_types)
pub extern "c" fn c_jit_call_v2(
  ctx_ptr : Int64,
  func_ptr : Int64,
  args : FixedArray[Int64],
  param_types : FixedArray[Int],
  num_args : Int,
  results : FixedArray[Int64],
  result_types : FixedArray[Int],
  num_results : Int,
) -> Int = "wasmoon_jit_call_v2"

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
