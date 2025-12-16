///|
/// JIT runtime FFI for executable memory management and code execution
/// Uses @jit_ffi package for C function declarations

// ============ Trap Handling ============

///|
/// Error for JIT trap
pub suberror JITTrap String derive(Show)

///|
/// Check if trap occurred and raise error if so
pub fn check_trap() -> Unit raise JITTrap {
  let code = @jit_ffi.c_jit_get_trap_code()
  if code != 0 {
    @jit_ffi.c_jit_clear_trap()
    let msg = match code {
      1 => "out of bounds memory access"
      2 => "call stack exhausted"
      _ => "unknown trap"
    }
    raise JITTrap(msg)
  }
}

// ============ Memory Grow Support ============

///|
/// Get memory_grow function pointer for JIT
pub fn get_memory_grow_ptr() -> Int64 {
  @jit_ffi.c_jit_get_memory_grow_ptr()
}

///|
/// Get get_memory_base function pointer for JIT
pub fn get_memory_base_ptr() -> Int64 {
  @jit_ffi.c_jit_get_memory_base_ptr()
}

///|
/// Get get_memory_size_bytes function pointer for JIT
pub fn get_memory_size_bytes_ptr() -> Int64 {
  @jit_ffi.c_jit_get_memory_size_bytes_ptr()
}

///|
/// Get memory_size function pointer for JIT (returns pages)
pub fn get_memory_size_ptr() -> Int64 {
  @jit_ffi.c_jit_get_memory_size_ptr()
}

// ============ Memory v2 functions (for v2 ABI) ============

///|
/// Get memory_grow v2 function pointer for JIT
pub fn get_memory_grow_v2_ptr() -> Int64 {
  @jit_ffi.c_jit_get_memory_grow_v2_ptr()
}

///|
/// Get get_memory_base v2 function pointer for JIT
pub fn get_memory_base_v2_ptr() -> Int64 {
  @jit_ffi.c_jit_get_memory_base_v2_ptr()
}

///|
/// Get get_memory_size_bytes v2 function pointer for JIT
pub fn get_memory_size_bytes_v2_ptr() -> Int64 {
  @jit_ffi.c_jit_get_memory_size_bytes_v2_ptr()
}

///|
/// Get memory_size v2 function pointer for JIT (returns pages)
pub fn get_memory_size_v2_ptr() -> Int64 {
  @jit_ffi.c_jit_get_memory_size_v2_ptr()
}

///|
/// Get current memory base from v2 context (for proper cleanup after memory.grow)
/// Returns the actual current memory base address, which may differ from the
/// originally allocated address if memory.grow caused a realloc.
pub fn get_current_memory_base_v2() -> Int64 {
  @jit_ffi.c_jit_get_current_memory_base_v2()
}

// ============ JIT Argument Trait ============

///|
/// Trait for types that can be passed as JIT function arguments
/// All types are converted to Int64 bit patterns for the C FFI
pub(open) trait JITArg {
  to_jit_arg(Self) -> Int64
}

///|
pub impl JITArg for Int64 with to_jit_arg(self) {
  self
}

///|
pub impl JITArg for Int with to_jit_arg(self) {
  self.to_int64()
}

///|
pub impl JITArg for Float with to_jit_arg(self) {
  self.reinterpret_as_int().to_int64()
}

///|
pub impl JITArg for Double with to_jit_arg(self) {
  self.reinterpret_as_int64()
}

// ============ JIT Context Wrapper ============

///|
/// JIT execution context (v2 ABI)
/// Uses fixed field offsets for JIT prologue:
/// +0: func_table, +8: indirect_table, +16: memory_base, +24: memory_size
priv struct JITContext {
  ctx_ptr : Int64
}

///|
/// Create a new JIT context (v2)
fn JITContext::new(total_funcs : Int) -> JITContext? {
  let ctx_ptr = @jit_ffi.c_jit_alloc_context_v2(total_funcs)
  if ctx_ptr == 0L {
    return None
  }
  Some(JITContext::{ ctx_ptr, })
}

///|
/// Set a function pointer in the context
fn JITContext::set_func(self : JITContext, idx : Int, func_ptr : Int64) -> Unit {
  @jit_ffi.c_jit_ctx_v2_set_func(self.ctx_ptr, idx, func_ptr)
}

///|
/// Allocate indirect table for call_indirect
fn JITContext::alloc_indirect_table(self : JITContext, count : Int) -> Bool {
  @jit_ffi.c_jit_ctx_v2_alloc_indirect_table(self.ctx_ptr, count) != 0
}

///|
/// Set an entry in indirect table (maps table_idx to func_idx with type_idx for type checking)
fn JITContext::set_indirect(
  self : JITContext,
  table_idx : Int,
  func_idx : Int,
  type_idx : Int,
) -> Unit {
  @jit_ffi.c_jit_ctx_v2_set_indirect(
    self.ctx_ptr,
    table_idx,
    func_idx,
    type_idx,
  )
}

///|
/// Set memory in the context
fn JITContext::set_memory(
  self : JITContext,
  mem_ptr : Int64,
  mem_size : Int64,
) -> Unit {
  @jit_ffi.c_jit_ctx_v2_set_memory(self.ctx_ptr, mem_ptr, mem_size)
}

///|
/// Set globals array in the context
fn JITContext::set_globals(self : JITContext, globals_ptr : Int64) -> Unit {
  @jit_ffi.c_jit_ctx_v2_set_globals(self.ctx_ptr, globals_ptr)
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
  // Convert Array[JITTable?] to FixedArray[Int64] of table pointers
  let table_ptrs = FixedArray::make(jit_tables.length(), 0L)
  for i, jit_table_opt in jit_tables {
    match jit_table_opt {
      Some(jit_table) => table_ptrs[i] = jit_table.table_ptr
      None => table_ptrs[i] = 0L // Null table pointer
    }
  }
  @jit_ffi.c_jit_ctx_v2_set_table_pointers(
    self.ctx_ptr,
    table_ptrs,
    jit_tables.length(),
  )
}

///|
/// JIT linear memory wrapper that handles memory.grow correctly.
/// When memory.grow is called, realloc may return a new address.
/// This wrapper ensures we free the correct (current) address.
pub struct JITMemory {
  priv initial_ptr : Int64 // For debugging only
}

///|
/// Allocate JIT linear memory
pub fn JITMemory::new(size : Int64) -> JITMemory? {
  let ptr = @jit_ffi.c_jit_alloc_memory(size)
  if ptr == 0L {
    return None
  }
  Some(JITMemory::{ initial_ptr: ptr })
}

///|
/// Get the initial memory pointer (for setting up JIT context)
pub fn JITMemory::ptr(self : JITMemory) -> Int64 {
  self.initial_ptr
}

///|
/// Free the memory. This gets the current memory base from the v2 context,
/// which may have changed due to memory.grow calling realloc.
pub fn JITMemory::free(self : JITMemory) -> Unit {
  // Get the current actual memory address (may have changed due to memory.grow)
  let current_ptr = get_current_memory_base_v2()
  if current_ptr != 0L {
    @jit_ffi.c_jit_free_memory(current_ptr)
  }
  ignore(self.initial_ptr) // Suppress unused warning
}

///|
/// Allocate linear memory for WASM (returns 0 on failure)
pub fn alloc_memory(size : Int64) -> Int64 {
  @jit_ffi.c_jit_alloc_memory(size)
}

///|
/// Free linear memory
pub fn free_memory(mem_ptr : Int64) -> Unit {
  @jit_ffi.c_jit_free_memory(mem_ptr)
}

///|
pub using @jit_ffi {c_jit_write_i64}

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
/// Activate this context for WASI calls (v2)
fn JITContext::activate(self : JITContext) -> Unit {
  @jit_ffi.c_jit_set_context_v2(self.ctx_ptr)
}

///|
/// Free the context (v2)
fn JITContext::free(self : JITContext) -> Unit {
  @jit_ffi.c_jit_free_context_v2(self.ctx_ptr)
}

// ============ Shared JIT Indirect Table ============

///|
/// Shared indirect table that can be used by multiple JIT modules
/// This enables cross-module table sharing and runtime modifications
pub struct JITTable {
  priv table_ptr : Int64 // Pointer to the shared C-side table
  priv size : Int
  priv max : Int?
  priv mut is_owned : Bool // Track if we should free this table
} derive(Show)

///|
/// Create a new shared JIT table
pub fn JITTable::new(size : Int, max : Int?) -> JITTable? {
  if size <= 0 {
    return None
  }
  let table_ptr = @jit_ffi.c_jit_alloc_shared_indirect_table(size)
  if table_ptr == 0L {
    return None
  }
  Some(JITTable::{ table_ptr, size, max, is_owned: true })
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
/// Free the shared table
pub fn JITTable::free(self : JITTable) -> Unit {
  if self.is_owned && self.table_ptr != 0L {
    @jit_ffi.c_jit_free_shared_indirect_table(self.table_ptr)
    self.is_owned = false
  }
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

// ============ Executable Code Block ============

///|
/// Executable code block
priv struct ExecCode {
  ptr : Int64
}

///|
/// Allocate and copy code to executable memory
fn ExecCode::new(code : Array[Int]) -> ExecCode? {
  let size = code.length()
  if size == 0 {
    return None
  }
  let ptr = @jit_ffi.c_jit_alloc_exec(size)
  if ptr == 0L {
    return None
  }
  // Copy code bytes
  let bytes = FixedArray::make(size, b'\x00')
  for i, b in code {
    bytes[i] = b.to_byte()
  }
  let result = @jit_ffi.c_jit_copy_code(ptr, bytes, size)
  if result != 0 {
    @jit_ffi.c_jit_free_exec(ptr) |> ignore
    return None
  }
  Some(ExecCode::{ ptr, })
}

///|
/// Free the executable memory
fn ExecCode::free(self : ExecCode) -> Unit {
  @jit_ffi.c_jit_free_exec(self.ptr) |> ignore
}

// ============ Multi-value Return Support ============

///|
/// Call a JIT function with multiple return values (v2 ABI)
/// X20 = context pointer, X0-X7 = int params, D0-D7 = float params
/// Returns 0 on success, trap code on error
fn JITContext::call_multi_return(
  self : JITContext,
  func_ptr : Int64,
  args : Array[Int64],
  param_types : Array[@types.ValueType],
  results : Array[Int64],
  result_types : Array[@types.ValueType],
) -> Unit raise JITTrap {
  let num_args = args.length()
  let num_results = result_types.length()
  // Convert args to FixedArray
  let args_fixed = FixedArray::make(num_args.max(1), 0L)
  for i in 0..<num_args {
    args_fixed[i] = args[i]
  }
  // Convert param_types to int codes
  let param_types_fixed = FixedArray::make(num_args.max(1), 0)
  for i in 0..<num_args {
    param_types_fixed[i] = if i < param_types.length() {
      match param_types[i] {
        I32 => 0
        I64 => 1
        F32 => 2
        F64 => 3
        // Reference types are 64-bit integer values (indices/pointers)
        FuncRef
        | ExternRef
        | RefFunc
        | RefExtern
        | RefFuncTyped(_)
        | RefNullFuncTyped(_) => 1
        V128 => abort("V128 not supported in JIT")
      }
    } else {
      0
    }
  }
  // Convert result_types to int codes
  let result_types_fixed = FixedArray::make(num_results.max(1), 0)
  for i in 0..<num_results {
    result_types_fixed[i] = match result_types[i] {
      I32 => 0
      I64 => 1
      F32 => 2
      F64 => 3
      // Reference types are 64-bit integer values (indices/pointers)
      FuncRef
      | ExternRef
      | RefFunc
      | RefExtern
      | RefFuncTyped(_)
      | RefNullFuncTyped(_) => 1
      V128 => abort("V128 not supported in JIT")
    }
  }
  // Prepare results array
  let results_fixed = FixedArray::make(num_results.max(1), 0L)
  // Call FFI with v2 ABI
  // X19 = ctx_ptr (context pointer), X0-X7 = int params, D0-D7 = float params
  let trap_code = @jit_ffi.c_jit_call_v2(
    self.ctx_ptr, // Context pointer for v2 ABI
    func_ptr,
    args_fixed,
    param_types_fixed,
    num_args,
    results_fixed,
    result_types_fixed,
    num_results,
  )
  if trap_code != 0 {
    let msg = match trap_code {
      1 => "out of bounds memory access"
      2 => "call stack exhausted"
      _ => "unknown trap"
    }
    raise JITTrap(msg)
  }
  // Copy results back
  for i in 0..<num_results {
    results[i] = results_fixed[i]
  }
}
