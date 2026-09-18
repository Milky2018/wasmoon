/// Managed executable-memory allocation.

///|
type ExecCodeHandle

///|
#borrow(code)
pub extern "c" fn alloc_exec_managed(
  code : FixedArray[Byte],
  size : Int,
) -> ExecCodeHandle = "wasmoon_jit_alloc_exec_managed"

///|
pub extern "c" fn stage_exec_managed(size : Int) -> ExecCodeHandle = "wasmoon_jit_stage_exec_managed"

///|
#borrow(exec_code, code)
pub extern "c" fn finalize_exec_managed(
  exec_code : ExecCodeHandle,
  code : FixedArray[Byte],
  size : Int,
) -> Int = "wasmoon_jit_finalize_exec_managed"

///|
#borrow(exec_code)
pub extern "c" fn release_exec_managed(exec_code : ExecCodeHandle) -> Int = "wasmoon_jit_release_exec_managed"

///|
#borrow(exec_code)
pub extern "c" fn exec_code_pointer(exec_code : ExecCodeHandle) -> Int64 = "wasmoon_jit_exec_code_ptr"
