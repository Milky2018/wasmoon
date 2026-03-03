///|
/// Call frame for function execution
struct Frame {
  func_idx : Int
  locals : Array[@types.Value]
  ip : Int // instruction pointer
  return_arity : Int // number of return values
} derive(Show)

///|
pub fn Frame::new(
  func_idx : Int,
  locals : Array[@types.Value],
  return_arity : Int,
) -> Frame {
  { func_idx, locals, ip: 0, return_arity }
}

///|
pub fn Frame::get_func_idx(self : Frame) -> Int {
  self.func_idx
}

///|
pub fn Frame::get_local(
  self : Frame,
  idx : Int,
) -> @types.Value raise RuntimeError {
  if idx < 0 || idx >= self.locals.length() {
    raise RuntimeError::TypeMismatch
  }
  self.locals[idx]
}

///|
pub fn Frame::set_local(
  self : Frame,
  idx : Int,
  value : @types.Value,
) -> Unit raise RuntimeError {
  if idx < 0 || idx >= self.locals.length() {
    raise RuntimeError::TypeMismatch
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
