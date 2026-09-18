///|
using @jit_ffi {
  type ExecCodeHandle,
  alloc_exec_managed,
  stage_exec_managed,
  finalize_exec_managed,
  release_exec_managed,
  exec_code_pointer,
}

///|
/// GC-managed executable code block wrapper.
struct ExecCode(ExecCodeHandle)

///|
/// Allocate and copy code to executable memory (GC-managed).
fn ExecCode::try_alloc(code : Array[Int]) -> ExecCode? {
  let size = code.length()
  if size == 0 {
    return None
  }
  let bytes = FixedArray::make(size, b'\x00')
  for i, b in code {
    bytes[i] = b.to_byte()
  }
  let ec = alloc_exec_managed(bytes, size)
  if exec_code_pointer(ec) != 0L {
    Some(ExecCode(ec))
  } else {
    None
  }
}

///|
fn ExecCode::try_stage(size : Int) -> ExecCode? {
  if size <= 0 {
    return None
  }
  let code = stage_exec_managed(size)
  if exec_code_pointer(code) == 0L {
    None
  } else {
    Some(ExecCode(code))
  }
}

///|
fn ExecCode::finalize(self : ExecCode, code : Array[Byte]) -> Bool {
  let size = code.length()
  let bytes = FixedArray::make(size, b'\x00')
  for index, byte in code {
    bytes[index] = byte
  }
  finalize_exec_managed(self.0, bytes, size) == 0
}

///|
fn ExecCode::release(self : ExecCode) -> Bool {
  release_exec_managed(self.0) == 0
}

///|
/// Get the function pointer from this executable code.
fn ExecCode::ptr(self : ExecCode) -> Int64 {
  exec_code_pointer(self.0)
}
