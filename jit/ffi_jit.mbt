///|
/// JIT runtime FFI for executable memory management and code execution
/// Uses @jit_ffi package for C function declarations

///|
pub using @jit_ffi {c_jit_write_i64, c_jit_read_i64}

// ============ Trap Handling ============

///|
/// Error for JIT trap
pub suberror JITTrap String derive(Show)

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

// ============ Memory v2 functions (for v2 ABI) ============

///|
/// Get memory_grow v2 function pointer for JIT
pub fn get_memory_grow_ptr() -> Int64 {
  @jit_ffi.c_jit_get_memory_grow_ptr()
}

///|
/// Get get_memory_base v2 function pointer for JIT
pub fn get_memory_base_ptr() -> Int64 {
  @jit_ffi.c_jit_get_memory_base_ptr()
}

///|
/// Get get_memory_size_bytes v2 function pointer for JIT
pub fn get_memory_size_bytes_ptr() -> Int64 {
  @jit_ffi.c_jit_get_memory_size_bytes_ptr()
}

///|
/// Get memory_size v2 function pointer for JIT (returns pages)
pub fn get_memory_size_ptr() -> Int64 {
  @jit_ffi.c_jit_get_memory_size_ptr()
}

///|
/// Get current memory base from v2 context (for proper cleanup after memory.grow)
/// Returns the actual current memory base address, which may differ from the
/// originally allocated address if memory.grow caused a realloc.
pub fn get_current_memory_base() -> Int64 {
  @jit_ffi.c_jit_get_current_memory_base()
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
/// JIT execution context (v3 ABI) - GC managed
/// Uses Cranelift-style on-demand loading from vmctx:
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
/// Create a new JIT context (v3) - GC managed
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
/// Set memory in the context
fn JITContext::set_memory(
  self : JITContext,
  mem_ptr : Int64,
  mem_size : Int64,
) -> Unit {
  @jit_ffi.c_jit_ctx_set_memory(self.ptr(), mem_ptr, mem_size)
}

///|
/// Set globals array in the context
fn JITContext::set_globals(self : JITContext, globals_ptr : Int64) -> Unit {
  @jit_ffi.c_jit_ctx_set_globals(self.ptr(), globals_ptr)
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
/// Allocate linear memory for WASM (returns 0 on failure)
/// NOTE: If you set the memory to a JITContext (via set_memory), the context
/// takes ownership and its finalizer will free the memory. Do NOT call
/// free_memory after that.
pub fn alloc_memory(size : Int64) -> Int64 {
  @jit_ffi.c_jit_alloc_memory(size)
}

///|
/// Free linear memory that was NOT set to a JITContext.
/// WARNING: Do NOT call this if memory was set to a context - the context's
/// finalizer will handle cleanup.
pub fn free_memory(mem_ptr : Int64) -> Unit {
  @jit_ffi.c_jit_free_memory(mem_ptr)
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
/// Activate this context for WASI calls (v2)
/// Uses reference counting to prevent GC from collecting this context
fn JITContext::activate(self : JITContext) -> Unit {
  @jit_ffi.c_jit_set_context_managed(self.ctx)
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
/// Call a JIT function with multiple return values (v3 ABI)
/// Uses JIT-generated trampolines following Cranelift's approach.
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
  let num_args = args.length()
  let num_results = result_types.length()

  // Convert param_types to int codes for trampoline generation
  let param_type_codes = FixedArray::make(num_args.max(1), 0)
  for i in 0..<num_args {
    param_type_codes[i] = if i < param_types.length() {
      value_type_to_code(param_types[i])
    } else {
      0
    }
  }

  // Convert result_types to int codes for trampoline generation
  let result_type_codes = FixedArray::make(num_results.max(1), 0)
  for i in 0..<num_results {
    result_type_codes[i] = value_type_to_code(result_types[i])
  }

  // Compute signature hash for trampoline cache lookup
  let sig_hash = compute_signature_hash(
    param_type_codes, num_args, result_type_codes, num_results,
  )

  // Get or generate trampoline
  let trampoline_ptr = match self.trampoline_cache.get(sig_hash) {
    Some(trampoline) => trampoline.ptr()
    None => {
      // Generate trampoline using emit_entry_trampoline
      let param_codes_arr : Array[Int] = []
      for i in 0..<num_args {
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
  // Each slot is 8 bytes (Int64)
  let values_len = num_args + num_results
  let values_vec = FixedArray::make(values_len.max(1), 0L)

  // Copy args to values_vec
  for i in 0..<num_args {
    values_vec[i] = args[i]
  }

  // Call via trampoline (Cranelift-style: all ABI complexity in JIT code)
  let trap_code = @jit_ffi.c_jit_call_trampoline(
    trampoline_ptr,
    self.ptr(),
    func_ptr,
    values_vec,
    values_len,
  )
  if trap_code != 0 {
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
  for i in 0..<num_results {
    results[i] = values_vec[num_args + i]
  }
}

///|
/// Convert ValueType to type code for trampoline generation
/// 0=I32, 1=I64, 2=F32, 3=F64
fn value_type_to_code(ty : @types.ValueType) -> Int {
  match ty {
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
    | RefNullFuncTyped(_)
    | AnyRef
    | ExnRef
    | NullRef
    | NullFuncRef
    | NullExnRef
    | NullExternRef => 1
    V128 => abort("V128 not supported in JIT")
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
