///|
/// Label for structured control flow (blocks, loops, if)
struct Label {
  arity : Int // number of values to keep when branching
  continuation : Int // instruction pointer to jump to
} derive(Show)

///|
/// Call frame for function execution
struct Frame {
  func_idx : Int
  locals : Array[@wasmoon.Value]
  ip : Int // instruction pointer
  return_arity : Int // number of return values
} derive(Show)

///|
pub fn Frame::new(
  func_idx : Int,
  locals : Array[@wasmoon.Value],
  return_arity : Int,
) -> Frame {
  { func_idx, locals, ip: 0, return_arity }
}

///|
pub fn Frame::get_local(
  self : Frame,
  idx : Int,
) -> @wasmoon.Value raise RuntimeError {
  if idx < 0 || idx >= self.locals.length() {
    raise RuntimeError::TypeMismatch
  }
  self.locals[idx]
}

///|
pub fn Frame::set_local(
  self : Frame,
  idx : Int,
  value : @wasmoon.Value,
) -> Unit raise RuntimeError {
  if idx < 0 || idx >= self.locals.length() {
    raise RuntimeError::TypeMismatch
  }
  self.locals[idx] = value
}
