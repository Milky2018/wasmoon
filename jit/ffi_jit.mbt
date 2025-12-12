///|
/// JIT runtime FFI for executable memory management and code execution
/// These functions call C functions defined in ffi_jit.c

// ============ Trap Handling ============

///|
/// Error for JIT trap
pub suberror JITTrap String derive(Show)

///|
/// Get trap code (0 = no trap, 1 = out of bounds memory access)
extern "c" fn c_jit_get_trap_code() -> Int = "wasmoon_jit_get_trap_code"

///|
/// Clear trap code
extern "c" fn c_jit_clear_trap() -> Unit = "wasmoon_jit_clear_trap"

///|
/// Check if trap occurred and raise error if so
pub fn check_trap() -> Unit raise JITTrap {
  let code = c_jit_get_trap_code()
  if code != 0 {
    c_jit_clear_trap()
    let msg = match code {
      1 => "out of bounds memory access"
      2 => "call stack exhausted"
      _ => "unknown trap"
    }
    raise JITTrap(msg)
  }
}

// ============ JIT Context Management ============

///|
/// Allocate a JIT context with function table
extern "c" fn c_jit_alloc_context(func_count : Int) -> Int64 = "wasmoon_jit_alloc_context"

///|
/// Free a JIT context
extern "c" fn c_jit_free_context(ctx_ptr : Int64) -> Unit = "wasmoon_jit_free_context"

///|
/// Set a function pointer in the context's function table
extern "c" fn c_jit_ctx_set_func(
  ctx_ptr : Int64,
  idx : Int,
  func_ptr : Int64,
) -> Unit = "wasmoon_jit_ctx_set_func"

///|
/// Set memory in the context
extern "c" fn c_jit_ctx_set_memory(
  ctx_ptr : Int64,
  mem_ptr : Int64,
  mem_size : Int64,
) -> Unit = "wasmoon_jit_ctx_set_memory"

///|
/// Get memory base from context
#warnings("-unused_value")
extern "c" fn c_jit_ctx_get_memory(ctx_ptr : Int64) -> Int64 = "wasmoon_jit_ctx_get_memory"

///|
/// Allocate linear memory for WASM
extern "c" fn c_jit_alloc_memory(size : Int64) -> Int64 = "wasmoon_jit_alloc_memory"

///|
/// Free linear memory
extern "c" fn c_jit_free_memory(mem_ptr : Int64) -> Unit = "wasmoon_jit_free_memory"

///|
/// Copy data to linear memory at offset
#borrow(data)
extern "c" fn c_jit_memory_init(
  mem_ptr : Int64,
  offset : Int64,
  data : FixedArray[Byte],
  size : Int,
) -> Int = "wasmoon_jit_memory_init"

///|
/// Get function table base address from context
extern "c" fn c_jit_ctx_get_func_table(ctx_ptr : Int64) -> Int64 = "wasmoon_jit_ctx_get_func_table"

///|
/// Allocate indirect table for call_indirect
extern "c" fn c_jit_ctx_alloc_indirect_table(
  ctx_ptr : Int64,
  count : Int,
) -> Int = "wasmoon_jit_ctx_alloc_indirect_table"

///|
/// Set an entry in indirect table (table_idx -> func_table[func_idx])
extern "c" fn c_jit_ctx_set_indirect(
  ctx_ptr : Int64,
  table_idx : Int,
  func_idx : Int,
) -> Unit = "wasmoon_jit_ctx_set_indirect"

///|
/// Set the global JIT context (for WASI trampolines)
extern "c" fn c_jit_set_context(ctx_ptr : Int64) -> Unit = "wasmoon_jit_set_context"

// ============ WASI Trampoline Pointers ============

///|
/// Get fd_write trampoline pointer
extern "c" fn c_jit_get_fd_write_ptr() -> Int64 = "wasmoon_jit_get_fd_write_ptr"

///|
/// Get proc_exit trampoline pointer
extern "c" fn c_jit_get_proc_exit_ptr() -> Int64 = "wasmoon_jit_get_proc_exit_ptr"

///|
/// Get fd_read trampoline pointer
extern "c" fn c_jit_get_fd_read_ptr() -> Int64 = "wasmoon_jit_get_fd_read_ptr"

///|
/// Get args_sizes_get trampoline pointer
extern "c" fn c_jit_get_args_sizes_get_ptr() -> Int64 = "wasmoon_jit_get_args_sizes_get_ptr"

///|
/// Get args_get trampoline pointer
extern "c" fn c_jit_get_args_get_ptr() -> Int64 = "wasmoon_jit_get_args_get_ptr"

///|
/// Get environ_sizes_get trampoline pointer
extern "c" fn c_jit_get_environ_sizes_get_ptr() -> Int64 = "wasmoon_jit_get_environ_sizes_get_ptr"

///|
/// Get environ_get trampoline pointer
extern "c" fn c_jit_get_environ_get_ptr() -> Int64 = "wasmoon_jit_get_environ_get_ptr"

///|
/// Get clock_time_get trampoline pointer
extern "c" fn c_jit_get_clock_time_get_ptr() -> Int64 = "wasmoon_jit_get_clock_time_get_ptr"

///|
/// Get random_get trampoline pointer
extern "c" fn c_jit_get_random_get_ptr() -> Int64 = "wasmoon_jit_get_random_get_ptr"

///|
/// Get fd_close trampoline pointer
extern "c" fn c_jit_get_fd_close_ptr() -> Int64 = "wasmoon_jit_get_fd_close_ptr"

///|
/// Get fd_fdstat_get trampoline pointer
extern "c" fn c_jit_get_fd_fdstat_get_ptr() -> Int64 = "wasmoon_jit_get_fd_fdstat_get_ptr"

///|
/// Get fd_prestat_get trampoline pointer
extern "c" fn c_jit_get_fd_prestat_get_ptr() -> Int64 = "wasmoon_jit_get_fd_prestat_get_ptr"

// ============ Spectest Trampolines ============

///|
/// Get spectest print trampoline pointer
extern "c" fn c_jit_get_spectest_print_ptr() -> Int64 = "wasmoon_jit_get_spectest_print_ptr"

///|
/// Get spectest print_i32 trampoline pointer
extern "c" fn c_jit_get_spectest_print_i32_ptr() -> Int64 = "wasmoon_jit_get_spectest_print_i32_ptr"

///|
/// Get spectest print_i64 trampoline pointer
extern "c" fn c_jit_get_spectest_print_i64_ptr() -> Int64 = "wasmoon_jit_get_spectest_print_i64_ptr"

///|
/// Get spectest print_f32 trampoline pointer
extern "c" fn c_jit_get_spectest_print_f32_ptr() -> Int64 = "wasmoon_jit_get_spectest_print_f32_ptr"

///|
/// Get spectest print_f64 trampoline pointer
extern "c" fn c_jit_get_spectest_print_f64_ptr() -> Int64 = "wasmoon_jit_get_spectest_print_f64_ptr"

///|
/// Get spectest print_i32_f32 trampoline pointer
extern "c" fn c_jit_get_spectest_print_i32_f32_ptr() -> Int64 = "wasmoon_jit_get_spectest_print_i32_f32_ptr"

///|
/// Get spectest print_f64_f64 trampoline pointer
extern "c" fn c_jit_get_spectest_print_f64_f64_ptr() -> Int64 = "wasmoon_jit_get_spectest_print_f64_f64_ptr"

// ============ Executable Memory Management ============

///|
/// Allocate executable memory
/// Returns pointer as Int64 (0 on failure)
extern "c" fn c_jit_alloc_exec(size : Int) -> Int64 = "wasmoon_jit_alloc_exec"

///|
/// Copy code to executable memory
/// Returns 0 on success, -1 on failure
#borrow(src)
extern "c" fn c_jit_copy_code(
  dest : Int64,
  src : FixedArray[Byte],
  size : Int,
) -> Int = "wasmoon_jit_copy_code"

///|
/// Free executable memory
/// Returns 0 on success, -1 on failure
extern "c" fn c_jit_free_exec(ptr : Int64) -> Int = "wasmoon_jit_free_exec"

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
/// JIT execution context
priv struct JITContext {
  ctx_ptr : Int64
  // func_table_ptr is used for direct calls (via func_idx)
  // Passed to JIT functions as X0, stored in X20
  // indirect_table_ptr is stored at func_table[-1] and loaded into X24 by prologue
  func_table_ptr : Int64
}

///|
/// Create a new JIT context
fn JITContext::new(total_funcs : Int) -> JITContext? {
  let ctx_ptr = c_jit_alloc_context(total_funcs)
  if ctx_ptr == 0L {
    return None
  }
  let func_table_ptr = c_jit_ctx_get_func_table(ctx_ptr)
  Some(JITContext::{ ctx_ptr, func_table_ptr })
}

///|
/// Set a function pointer in the context
fn JITContext::set_func(self : JITContext, idx : Int, func_ptr : Int64) -> Unit {
  c_jit_ctx_set_func(self.ctx_ptr, idx, func_ptr)
}

///|
/// Allocate indirect table for call_indirect
/// The C code stores the indirect_table pointer at func_table[-1]
fn JITContext::alloc_indirect_table(self : JITContext, count : Int) -> Bool {
  c_jit_ctx_alloc_indirect_table(self.ctx_ptr, count) != 0
}

///|
/// Set an entry in indirect table (maps table_idx to func_idx)
fn JITContext::set_indirect(
  self : JITContext,
  table_idx : Int,
  func_idx : Int,
) -> Unit {
  c_jit_ctx_set_indirect(self.ctx_ptr, table_idx, func_idx)
}

///|
/// Set memory in the context
fn JITContext::set_memory(
  self : JITContext,
  mem_ptr : Int64,
  mem_size : Int64,
) -> Unit {
  c_jit_ctx_set_memory(self.ctx_ptr, mem_ptr, mem_size)
}

///|
/// Allocate linear memory for WASM (returns 0 on failure)
pub fn alloc_memory(size : Int64) -> Int64 {
  c_jit_alloc_memory(size)
}

///|
/// Free linear memory
pub fn free_memory(mem_ptr : Int64) -> Unit {
  c_jit_free_memory(mem_ptr)
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
  c_jit_memory_init(mem_ptr, offset, bytes, size) == 0
}

///|
/// Activate this context for WASI calls
fn JITContext::activate(self : JITContext) -> Unit {
  c_jit_set_context(self.ctx_ptr)
}

///|
/// Free the context
fn JITContext::free(self : JITContext) -> Unit {
  c_jit_free_context(self.ctx_ptr)
}

///|
/// Get fd_write trampoline pointer
pub fn get_fd_write_ptr() -> Int64 {
  c_jit_get_fd_write_ptr()
}

///|
/// Get proc_exit trampoline pointer
pub fn get_proc_exit_ptr() -> Int64 {
  c_jit_get_proc_exit_ptr()
}

///|
/// Get fd_read trampoline pointer
pub fn get_fd_read_ptr() -> Int64 {
  c_jit_get_fd_read_ptr()
}

///|
/// Get args_sizes_get trampoline pointer
pub fn get_args_sizes_get_ptr() -> Int64 {
  c_jit_get_args_sizes_get_ptr()
}

///|
/// Get args_get trampoline pointer
pub fn get_args_get_ptr() -> Int64 {
  c_jit_get_args_get_ptr()
}

///|
/// Get environ_sizes_get trampoline pointer
pub fn get_environ_sizes_get_ptr() -> Int64 {
  c_jit_get_environ_sizes_get_ptr()
}

///|
/// Get environ_get trampoline pointer
pub fn get_environ_get_ptr() -> Int64 {
  c_jit_get_environ_get_ptr()
}

///|
/// Get clock_time_get trampoline pointer
pub fn get_clock_time_get_ptr() -> Int64 {
  c_jit_get_clock_time_get_ptr()
}

///|
/// Get random_get trampoline pointer
pub fn get_random_get_ptr() -> Int64 {
  c_jit_get_random_get_ptr()
}

///|
/// Get fd_close trampoline pointer
pub fn get_fd_close_ptr() -> Int64 {
  c_jit_get_fd_close_ptr()
}

///|
/// Get fd_fdstat_get trampoline pointer
pub fn get_fd_fdstat_get_ptr() -> Int64 {
  c_jit_get_fd_fdstat_get_ptr()
}

///|
/// Get fd_prestat_get trampoline pointer
pub fn get_fd_prestat_get_ptr() -> Int64 {
  c_jit_get_fd_prestat_get_ptr()
}

///|
/// Get spectest print trampoline pointer
pub fn get_spectest_print_ptr() -> Int64 {
  c_jit_get_spectest_print_ptr()
}

///|
/// Get spectest print_i32 trampoline pointer
pub fn get_spectest_print_i32_ptr() -> Int64 {
  c_jit_get_spectest_print_i32_ptr()
}

///|
/// Get spectest print_i64 trampoline pointer
pub fn get_spectest_print_i64_ptr() -> Int64 {
  c_jit_get_spectest_print_i64_ptr()
}

///|
/// Get spectest print_f32 trampoline pointer
pub fn get_spectest_print_f32_ptr() -> Int64 {
  c_jit_get_spectest_print_f32_ptr()
}

///|
/// Get spectest print_f64 trampoline pointer
pub fn get_spectest_print_f64_ptr() -> Int64 {
  c_jit_get_spectest_print_f64_ptr()
}

///|
/// Get spectest print_i32_f32 trampoline pointer
pub fn get_spectest_print_i32_f32_ptr() -> Int64 {
  c_jit_get_spectest_print_i32_f32_ptr()
}

///|
/// Get spectest print_f64_f64 trampoline pointer
pub fn get_spectest_print_f64_f64_ptr() -> Int64 {
  c_jit_get_spectest_print_f64_f64_ptr()
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
  let ptr = c_jit_alloc_exec(size)
  if ptr == 0L {
    return None
  }
  // Copy code bytes
  let bytes = FixedArray::make(size, b'\x00')
  for i, b in code {
    bytes[i] = b.to_byte()
  }
  let result = c_jit_copy_code(ptr, bytes, size)
  if result != 0 {
    c_jit_free_exec(ptr) |> ignore
    return None
  }
  Some(ExecCode::{ ptr, })
}

///|
/// Free the executable memory
fn ExecCode::free(self : ExecCode) -> Unit {
  c_jit_free_exec(self.ptr) |> ignore
}

// ============ Multi-value Return Support ============

///|
/// C FFI for multi-value return calls
/// result_types uses: 0=I32, 1=I64, 2=F32, 3=F64
#borrow(args, results, result_types)
extern "c" fn c_jit_call_multi_return(
  func_ptr : Int64,
  func_table_ptr : Int64,
  args : FixedArray[Int64],
  num_args : Int,
  results : FixedArray[Int64],
  result_types : FixedArray[Int],
  num_results : Int,
) -> Int = "wasmoon_jit_call_multi_return"

///|
/// Call a JIT function with multiple return values
/// Returns 0 on success, trap code on error
fn JITContext::call_multi_return(
  self : JITContext,
  func_ptr : Int64,
  args : Array[Int64],
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
  // Convert result_types to int codes
  let types_fixed = FixedArray::make(num_results, 0)
  for i in 0..<num_results {
    types_fixed[i] = match result_types[i] {
      I32 => 0
      I64 => 1
      F32 => 2
      F64 => 3
      _ => 0
    }
  }
  // Prepare results array
  let results_fixed = FixedArray::make(num_results.max(1), 0L)
  // Call FFI
  // Pass func_table_ptr to X0 (stored in X20 for direct calls)
  // indirect_table_ptr is stored in func_table[-1] and loaded into X24 in prologue
  let trap_code = c_jit_call_multi_return(
    func_ptr,
    self.func_table_ptr, // Use func_table for direct calls
    args_fixed,
    num_args,
    results_fixed,
    types_fixed,
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
