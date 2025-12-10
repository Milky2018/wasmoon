///|
/// JIT runtime FFI for executable memory management and code execution
/// These functions call C functions defined in ffi_jit.c

// ============ Trap Handling ============

///|
/// Error for JIT trap
pub suberror JITTrap String

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
    raise JITTrap("out of bounds memory access")
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

// ============ Context-aware JIT function calls ============

///|
/// Call JIT function with context: () -> i64
extern "c" fn c_jit_call_ctx_void_i64(
  func_ptr : Int64,
  func_table_ptr : Int64,
) -> Int64 = "wasmoon_jit_call_ctx_void_i64"

///|
/// Call JIT function with context: (i64) -> i64
#warnings("-unused_value")
extern "c" fn c_jit_call_ctx_i64_i64(
  func_ptr : Int64,
  func_table_ptr : Int64,
  arg0 : Int64,
) -> Int64 = "wasmoon_jit_call_ctx_i64_i64"

///|
/// Call JIT function with context: (i64, i64) -> i64
#warnings("-unused_value")
extern "c" fn c_jit_call_ctx_i64i64_i64(
  func_ptr : Int64,
  func_table_ptr : Int64,
  arg0 : Int64,
  arg1 : Int64,
) -> Int64 = "wasmoon_jit_call_ctx_i64i64_i64"

///|
/// Call JIT function with context: () -> void
extern "c" fn c_jit_call_ctx_void_void(
  func_ptr : Int64,
  func_table_ptr : Int64,
) -> Unit = "wasmoon_jit_call_ctx_void_void"

///|
/// Call JIT function with context: (i64) -> void
#warnings("-unused_value")
extern "c" fn c_jit_call_ctx_i64_void(
  func_ptr : Int64,
  func_table_ptr : Int64,
  arg0 : Int64,
) -> Unit = "wasmoon_jit_call_ctx_i64_void"

///|
/// Call JIT function with context: (i64, i64) -> void
#warnings("-unused_value")
extern "c" fn c_jit_call_ctx_i64i64_void(
  func_ptr : Int64,
  func_table_ptr : Int64,
  arg0 : Int64,
  arg1 : Int64,
) -> Unit = "wasmoon_jit_call_ctx_i64i64_void"

// ============ Float Return Value Calls ============
// AAPCS64: float/double returns are in D0, not X0

///|
/// Call JIT function with context: () -> f32
extern "c" fn c_jit_call_ctx_void_f32(
  func_ptr : Int64,
  func_table_ptr : Int64,
) -> Float = "wasmoon_jit_call_ctx_void_f32"

///|
/// Call JIT function with context: (i64) -> f32
extern "c" fn c_jit_call_ctx_i64_f32(
  func_ptr : Int64,
  func_table_ptr : Int64,
  arg0 : Int64,
) -> Float = "wasmoon_jit_call_ctx_i64_f32"

///|
/// Call JIT function with context: (i64, i64) -> f32
extern "c" fn c_jit_call_ctx_i64i64_f32(
  func_ptr : Int64,
  func_table_ptr : Int64,
  arg0 : Int64,
  arg1 : Int64,
) -> Float = "wasmoon_jit_call_ctx_i64i64_f32"

///|
/// Call JIT function with context: () -> f64
extern "c" fn c_jit_call_ctx_void_f64(
  func_ptr : Int64,
  func_table_ptr : Int64,
) -> Double = "wasmoon_jit_call_ctx_void_f64"

///|
/// Call JIT function with context: (i64) -> f64
extern "c" fn c_jit_call_ctx_i64_f64(
  func_ptr : Int64,
  func_table_ptr : Int64,
  arg0 : Int64,
) -> Double = "wasmoon_jit_call_ctx_i64_f64"

///|
/// Call JIT function with context: (i64, i64) -> f64
extern "c" fn c_jit_call_ctx_i64i64_f64(
  func_ptr : Int64,
  func_table_ptr : Int64,
  arg0 : Int64,
  arg1 : Int64,
) -> Double = "wasmoon_jit_call_ctx_i64i64_f64"

// ============ Legacy JIT function calls (without context) ============

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

///|
/// Call JIT function: () -> i64
extern "c" fn c_jit_call_void_i64(func_ptr : Int64) -> Int64 = "wasmoon_jit_call_void_i64"

///|
/// Call JIT function: (i64) -> i64
extern "c" fn c_jit_call_i64_i64(func_ptr : Int64, arg0 : Int64) -> Int64 = "wasmoon_jit_call_i64_i64"

///|
/// Call JIT function: (i64, i64) -> i64
extern "c" fn c_jit_call_i64i64_i64(
  func_ptr : Int64,
  arg0 : Int64,
  arg1 : Int64,
) -> Int64 = "wasmoon_jit_call_i64i64_i64"

///|
/// Call JIT function: (i64, i64, i64) -> i64
extern "c" fn c_jit_call_i64i64i64_i64(
  func_ptr : Int64,
  arg0 : Int64,
  arg1 : Int64,
  arg2 : Int64,
) -> Int64 = "wasmoon_jit_call_i64i64i64_i64"

///|
/// Call JIT function: (i64, i64, i64, i64) -> i64
extern "c" fn c_jit_call_i64i64i64i64_i64(
  func_ptr : Int64,
  arg0 : Int64,
  arg1 : Int64,
  arg2 : Int64,
  arg3 : Int64,
) -> Int64 = "wasmoon_jit_call_i64i64i64i64_i64"

///|
/// Call JIT function: () -> void
extern "c" fn c_jit_call_void_void(func_ptr : Int64) -> Unit = "wasmoon_jit_call_void_void"

///|
/// Call JIT function: (i64) -> void
extern "c" fn c_jit_call_i64_void(func_ptr : Int64, arg0 : Int64) -> Unit = "wasmoon_jit_call_i64_void"

///|
/// Call JIT function: (i64, i64) -> void
extern "c" fn c_jit_call_i64i64_void(
  func_ptr : Int64,
  arg0 : Int64,
  arg1 : Int64,
) -> Unit = "wasmoon_jit_call_i64i64_void"

///|
/// Call JIT function: (i64, i64, i64) -> void
extern "c" fn c_jit_call_i64i64i64_void(
  func_ptr : Int64,
  arg0 : Int64,
  arg1 : Int64,
  arg2 : Int64,
) -> Unit = "wasmoon_jit_call_i64i64i64_void"

///|
/// Call JIT function: (i64, i64, i64, i64) -> void
extern "c" fn c_jit_call_i64i64i64i64_void(
  func_ptr : Int64,
  arg0 : Int64,
  arg1 : Int64,
  arg2 : Int64,
  arg3 : Int64,
) -> Unit = "wasmoon_jit_call_i64i64i64i64_void"

///|
/// Debug: print machine code bytes
extern "c" fn c_jit_debug_print_code(ptr : Int64, size : Int) -> Unit = "wasmoon_jit_debug_print_code"

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
pub(all) struct JITContext {
  ctx_ptr : Int64
  func_table_ptr : Int64
}

///|
/// Create a new JIT context
pub fn JITContext::new(total_funcs : Int) -> JITContext? {
  let ctx_ptr = c_jit_alloc_context(total_funcs)
  if ctx_ptr == 0L {
    return None
  }
  let func_table_ptr = c_jit_ctx_get_func_table(ctx_ptr)
  Some(JITContext::{ ctx_ptr, func_table_ptr })
}

///|
/// Set a function pointer in the context
pub fn JITContext::set_func(
  self : JITContext,
  idx : Int,
  func_ptr : Int64,
) -> Unit {
  c_jit_ctx_set_func(self.ctx_ptr, idx, func_ptr)
}

///|
/// Set memory in the context
pub fn JITContext::set_memory(
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
pub fn JITContext::activate(self : JITContext) -> Unit {
  c_jit_set_context(self.ctx_ptr)
}

// ============ Internal Call Functions ============
// These are the low-level wrappers around C FFI, used by generic call functions

///|
fn JITContext::call_void_i64(
  self : JITContext,
  func_ptr : Int64,
) -> Int64 raise JITTrap {
  let result = c_jit_call_ctx_void_i64(func_ptr, self.func_table_ptr)
  check_trap()
  result
}

///|
fn JITContext::call_void_void(
  self : JITContext,
  func_ptr : Int64,
) -> Unit raise JITTrap {
  c_jit_call_ctx_void_void(func_ptr, self.func_table_ptr)
  check_trap()
}

///|
fn JITContext::call_i64_i64(
  self : JITContext,
  func_ptr : Int64,
  arg0 : Int64,
) -> Int64 raise JITTrap {
  let result = c_jit_call_ctx_i64_i64(func_ptr, self.func_table_ptr, arg0)
  check_trap()
  result
}

///|
fn JITContext::call_i64i64_i64(
  self : JITContext,
  func_ptr : Int64,
  arg0 : Int64,
  arg1 : Int64,
) -> Int64 raise JITTrap {
  let result = c_jit_call_ctx_i64i64_i64(
    func_ptr,
    self.func_table_ptr,
    arg0,
    arg1,
  )
  check_trap()
  result
}

///|
fn JITContext::call_i64_void(
  self : JITContext,
  func_ptr : Int64,
  arg0 : Int64,
) -> Unit raise JITTrap {
  c_jit_call_ctx_i64_void(func_ptr, self.func_table_ptr, arg0)
  check_trap()
}

///|
fn JITContext::call_i64i64_void(
  self : JITContext,
  func_ptr : Int64,
  arg0 : Int64,
  arg1 : Int64,
) -> Unit raise JITTrap {
  c_jit_call_ctx_i64i64_void(func_ptr, self.func_table_ptr, arg0, arg1)
  check_trap()
}

///|
fn JITContext::call_void_f32(
  self : JITContext,
  func_ptr : Int64,
) -> Float raise JITTrap {
  let result = c_jit_call_ctx_void_f32(func_ptr, self.func_table_ptr)
  check_trap()
  result
}

///|
fn JITContext::call_i64_f32(
  self : JITContext,
  func_ptr : Int64,
  arg0 : Int64,
) -> Float raise JITTrap {
  let result = c_jit_call_ctx_i64_f32(func_ptr, self.func_table_ptr, arg0)
  check_trap()
  result
}

///|
fn JITContext::call_i64i64_f32(
  self : JITContext,
  func_ptr : Int64,
  arg0 : Int64,
  arg1 : Int64,
) -> Float raise JITTrap {
  let result = c_jit_call_ctx_i64i64_f32(
    func_ptr,
    self.func_table_ptr,
    arg0,
    arg1,
  )
  check_trap()
  result
}

///|
fn JITContext::call_void_f64(
  self : JITContext,
  func_ptr : Int64,
) -> Double raise JITTrap {
  let result = c_jit_call_ctx_void_f64(func_ptr, self.func_table_ptr)
  check_trap()
  result
}

///|
fn JITContext::call_i64_f64(
  self : JITContext,
  func_ptr : Int64,
  arg0 : Int64,
) -> Double raise JITTrap {
  let result = c_jit_call_ctx_i64_f64(func_ptr, self.func_table_ptr, arg0)
  check_trap()
  result
}

///|
fn JITContext::call_i64i64_f64(
  self : JITContext,
  func_ptr : Int64,
  arg0 : Int64,
  arg1 : Int64,
) -> Double raise JITTrap {
  let result = c_jit_call_ctx_i64i64_f64(
    func_ptr,
    self.func_table_ptr,
    arg0,
    arg1,
  )
  check_trap()
  result
}

// ============ Generic Call Functions ============
// These use the JITArg trait to accept any convertible argument type

///|
/// Call with 0 args, return i64
pub fn JITContext::call_i64_0(
  self : JITContext,
  func_ptr : Int64,
) -> Int64 raise JITTrap {
  self.call_void_i64(func_ptr)
}

///|
/// Call with 1 arg, return i64
pub fn[T : JITArg] JITContext::call_i64_1(
  self : JITContext,
  func_ptr : Int64,
  arg0 : T,
) -> Int64 raise JITTrap {
  self.call_i64_i64(func_ptr, arg0.to_jit_arg())
}

///|
/// Call with 2 args, return i64
pub fn[T1 : JITArg, T2 : JITArg] JITContext::call_i64_2(
  self : JITContext,
  func_ptr : Int64,
  arg0 : T1,
  arg1 : T2,
) -> Int64 raise JITTrap {
  self.call_i64i64_i64(func_ptr, arg0.to_jit_arg(), arg1.to_jit_arg())
}

///|
/// Call with 0 args, return f32
pub fn JITContext::call_f32_0(
  self : JITContext,
  func_ptr : Int64,
) -> Float raise JITTrap {
  self.call_void_f32(func_ptr)
}

///|
/// Call with 1 arg, return f32
pub fn[T : JITArg] JITContext::call_f32_1(
  self : JITContext,
  func_ptr : Int64,
  arg0 : T,
) -> Float raise JITTrap {
  self.call_i64_f32(func_ptr, arg0.to_jit_arg())
}

///|
/// Call with 2 args, return f32
pub fn[T1 : JITArg, T2 : JITArg] JITContext::call_f32_2(
  self : JITContext,
  func_ptr : Int64,
  arg0 : T1,
  arg1 : T2,
) -> Float raise JITTrap {
  self.call_i64i64_f32(func_ptr, arg0.to_jit_arg(), arg1.to_jit_arg())
}

///|
/// Call with 0 args, return f64
pub fn JITContext::call_f64_0(
  self : JITContext,
  func_ptr : Int64,
) -> Double raise JITTrap {
  self.call_void_f64(func_ptr)
}

///|
/// Call with 1 arg, return f64
pub fn[T : JITArg] JITContext::call_f64_1(
  self : JITContext,
  func_ptr : Int64,
  arg0 : T,
) -> Double raise JITTrap {
  self.call_i64_f64(func_ptr, arg0.to_jit_arg())
}

///|
/// Call with 2 args, return f64
pub fn[T1 : JITArg, T2 : JITArg] JITContext::call_f64_2(
  self : JITContext,
  func_ptr : Int64,
  arg0 : T1,
  arg1 : T2,
) -> Double raise JITTrap {
  self.call_i64i64_f64(func_ptr, arg0.to_jit_arg(), arg1.to_jit_arg())
}

///|
/// Call with 0 args, no return
pub fn JITContext::call_void_0(
  self : JITContext,
  func_ptr : Int64,
) -> Unit raise JITTrap {
  self.call_void_void(func_ptr)
}

///|
/// Call with 1 arg, no return
pub fn[T : JITArg] JITContext::call_void_1(
  self : JITContext,
  func_ptr : Int64,
  arg0 : T,
) -> Unit raise JITTrap {
  self.call_i64_void(func_ptr, arg0.to_jit_arg())
}

///|
/// Call with 2 args, no return
pub fn[T1 : JITArg, T2 : JITArg] JITContext::call_void_2(
  self : JITContext,
  func_ptr : Int64,
  arg0 : T1,
  arg1 : T2,
) -> Unit raise JITTrap {
  self.call_i64i64_void(func_ptr, arg0.to_jit_arg(), arg1.to_jit_arg())
}

///|
/// Free the context
pub fn JITContext::free(self : JITContext) -> Unit {
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
pub(all) struct ExecCode {
  ptr : Int64
  size : Int
}

///|
/// Allocate and copy code to executable memory
pub fn ExecCode::new(code : Array[Int]) -> ExecCode? {
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
  Some(ExecCode::{ ptr, size })
}

///|
/// Create from Bytes
pub fn ExecCode::from_bytes(code : Bytes) -> ExecCode? {
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
  for i in 0..<size {
    bytes[i] = code[i]
  }
  let result = c_jit_copy_code(ptr, bytes, size)
  if result != 0 {
    c_jit_free_exec(ptr) |> ignore
    return None
  }
  Some(ExecCode::{ ptr, size })
}

///|
/// Free the executable memory
pub fn ExecCode::free(self : ExecCode) -> Unit {
  c_jit_free_exec(self.ptr) |> ignore
}

///|
/// Call with no args, return i64
pub fn ExecCode::call_void_i64(self : ExecCode) -> Int64 {
  c_jit_call_void_i64(self.ptr)
}

///|
/// Call with 1 arg, return i64
pub fn ExecCode::call_i64_i64(self : ExecCode, arg0 : Int64) -> Int64 {
  c_jit_call_i64_i64(self.ptr, arg0)
}

///|
/// Call with 2 args, return i64
pub fn ExecCode::call_i64i64_i64(
  self : ExecCode,
  arg0 : Int64,
  arg1 : Int64,
) -> Int64 {
  c_jit_call_i64i64_i64(self.ptr, arg0, arg1)
}

///|
/// Call with 3 args, return i64
pub fn ExecCode::call_i64i64i64_i64(
  self : ExecCode,
  arg0 : Int64,
  arg1 : Int64,
  arg2 : Int64,
) -> Int64 {
  c_jit_call_i64i64i64_i64(self.ptr, arg0, arg1, arg2)
}

///|
/// Call with 4 args, return i64
pub fn ExecCode::call_i64i64i64i64_i64(
  self : ExecCode,
  arg0 : Int64,
  arg1 : Int64,
  arg2 : Int64,
  arg3 : Int64,
) -> Int64 {
  c_jit_call_i64i64i64i64_i64(self.ptr, arg0, arg1, arg2, arg3)
}

///|
/// Call with no args, no return
pub fn ExecCode::call_void_void(self : ExecCode) -> Unit {
  c_jit_call_void_void(self.ptr)
}

///|
/// Call with 1 arg, no return
pub fn ExecCode::call_i64_void(self : ExecCode, arg0 : Int64) -> Unit {
  c_jit_call_i64_void(self.ptr, arg0)
}

///|
/// Call with 2 args, no return
pub fn ExecCode::call_i64i64_void(
  self : ExecCode,
  arg0 : Int64,
  arg1 : Int64,
) -> Unit {
  c_jit_call_i64i64_void(self.ptr, arg0, arg1)
}

///|
/// Call with 3 args, no return
pub fn ExecCode::call_i64i64i64_void(
  self : ExecCode,
  arg0 : Int64,
  arg1 : Int64,
  arg2 : Int64,
) -> Unit {
  c_jit_call_i64i64i64_void(self.ptr, arg0, arg1, arg2)
}

///|
/// Call with 4 args, no return
pub fn ExecCode::call_i64i64i64i64_void(
  self : ExecCode,
  arg0 : Int64,
  arg1 : Int64,
  arg2 : Int64,
  arg3 : Int64,
) -> Unit {
  c_jit_call_i64i64i64i64_void(self.ptr, arg0, arg1, arg2, arg3)
}

///|
/// Debug: print the machine code
pub fn ExecCode::debug_print(self : ExecCode) -> Unit {
  c_jit_debug_print_code(self.ptr, self.size)
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
pub fn JITContext::call_multi_return(
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
  let trap_code = c_jit_call_multi_return(
    func_ptr,
    self.func_table_ptr,
    args_fixed,
    num_args,
    results_fixed,
    types_fixed,
    num_results,
  )
  if trap_code != 0 {
    raise JITTrap("out of bounds memory access")
  }
  // Copy results back
  for i in 0..<num_results {
    results[i] = results_fixed[i]
  }
}
