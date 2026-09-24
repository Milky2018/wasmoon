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
/// Shared managed linear-memory allocation. Each handle keeps the descriptor
/// and its backing memory alive independently of a Store or JIT context.
pub type MemoryDescriptor

///|
pub extern "c" fn MemoryDescriptor::null() -> MemoryDescriptor = "wasmoon_memory_descriptor_empty"

///|
#borrow(self)
pub extern "c" fn MemoryDescriptor::is_null(self : MemoryDescriptor) -> Bool = "wasmoon_memory_descriptor_is_empty"

///|
#borrow(a, b)
extern "c" fn descriptor_equal(
  a : MemoryDescriptor,
  b : MemoryDescriptor,
) -> Bool = "wasmoon_memory_descriptor_equal"

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
