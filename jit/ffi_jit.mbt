///|
/// JIT runtime FFI for executable memory management and code execution
/// These functions call C functions defined in ffi_jit.c

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
