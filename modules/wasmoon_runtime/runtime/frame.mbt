///|
/// Call frame for function execution
struct Frame {
  func_idx : Int32
  locals : Array[@types.Value]
  ip : Int32 // instruction pointer
  return_arity : Int32 // number of return values
} derive(Debug)

///|
pub fn Frame::Frame(
  func_idx : Int32,
  locals : Array[@types.Value],
  return_arity : Int32,
) -> Frame {
  { func_idx, locals, ip: 0, return_arity, }
}

///|
pub fn Frame::get_func_idx(self : Frame) -> Int32 {
  self.func_idx
}

///|
pub fn Frame::get_local(
  self : Frame,
  idx : Int32,
) -> @types.Value raise RuntimeError {
  if idx < 0 || idx >= self.locals.length() {
    raise TypeMismatch
  }
  self.locals[idx]
}

///|
pub fn Frame::set_local(
  self : Frame,
  idx : Int32,
  value : @types.Value,
) -> Unit raise RuntimeError {
  if idx < 0 || idx >= self.locals.length() {
    raise TypeMismatch
  }
  self.locals[idx] = value
}

///|
/// Snapshot local values (for GC root collection/debugging)
pub fn Frame::locals_values(self : Frame) -> Array[@types.Value] {
  let locals : Array[@types.Value] = []
  for local_value in self.locals {
    locals.push(local_value)
  }
  locals
}
