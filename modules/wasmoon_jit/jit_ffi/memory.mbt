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

///|
/// Borrowed pointer to a C-owned linear-memory descriptor. The pointer does not
/// retain the descriptor; callers must keep its Store or explicit owner alive.
#external
pub type MemoryDescriptor

///|
pub extern "c" fn MemoryDescriptor::null() -> MemoryDescriptor = "wasmoon_native_pointer_null"

///|
pub extern "c" fn MemoryDescriptor::is_null(self : MemoryDescriptor) -> Bool = "wasmoon_native_pointer_is_null"

///|
extern "c" fn descriptor_equal(
  a : MemoryDescriptor,
  b : MemoryDescriptor,
) -> Bool = "wasmoon_native_pointer_equal"

///|
pub impl Eq for MemoryDescriptor with fn equal(a, b) {
  descriptor_equal(a, b)
}

///|
pub impl Debug for MemoryDescriptor with fn to_repr(self) {
  Repr::literal(
    if self.is_null() {
      "MemoryDescriptor(null)"
    } else {
      "MemoryDescriptor(non-null)"
    },
  )
}

///|
pub extend MemoryDescriptor with Eq::{equal, not_equal}

///|
pub extend MemoryDescriptor with Debug::{to_repr}
