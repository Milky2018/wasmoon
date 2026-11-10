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
fn ExecCode::try_alloc(
  code : Array[Int32],
  reservation~ : @jit_ffi.Reservation? = None,
) -> ExecCode? {
  let size = code.length()
  if size == 0 {
    return None
  }
  let bytes = FixedArray::makei(size, i => code[i].to_byte())
  let ec = alloc_exec_managed(bytes, size)
  if exec_code_pointer(ec) != 0L {
    if reservation is Some(reservation) && !ec.bind_reservation(reservation) {
      return None
    }
    Some(ExecCode(ec))
  } else {
    None
  }
}

///|
fn ExecCode::try_stage(
  size : Int32,
  code_bytes~ : Int32 = size,
  reservation~ : @jit_ffi.Reservation? = None,
) -> ExecCode? {
  if size <= 0 {
    return None
  }
  let code = stage_exec_managed(size, code_bytes~)
  if exec_code_pointer(code) == 0L {
    None
  } else {
    if reservation is Some(reservation) && !code.bind_reservation(reservation) {
      return None
    }
    Some(ExecCode(code))
  }
}

///|
fn ExecCode::finalize(self : ExecCode, code : Array[Byte]) -> Bool {
  let size = code.length()
  let bytes = FixedArray::makei(size, i => code[i])
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
