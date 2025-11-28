///|
/// @types.Value stack for operands
struct Stack {
  values : Array[@types.Value]
  mut sp : Int // stack pointer
} derive(Show)

///|
pub fn Stack::new() -> Stack {
  { values: [], sp: 0 }
}

///|
pub fn Stack::push(
  self : Stack,
  value : @types.Value,
) -> Unit raise RuntimeError {
  if self.sp >= 10000 { // arbitrary limit
    raise StackOverflow
  }
  if self.sp >= self.values.length() {
    self.values.push(value)
  } else {
    self.values[self.sp] = value
  }
  self.sp = self.sp + 1
}

///|
pub fn Stack::pop(self : Stack) -> @types.Value raise RuntimeError {
  if self.sp <= 0 {
    raise StackUnderflow
  }
  self.sp = self.sp - 1
  self.values[self.sp]
}

///|
pub fn Stack::peek(self : Stack) -> @types.Value raise RuntimeError {
  if self.sp <= 0 {
    raise StackUnderflow
  }
  self.values[self.sp - 1]
}

///|
pub fn Stack::pop_i32(self : Stack) -> Int raise RuntimeError {
  match self.pop() {
    I32(n) => n
    _ => raise TypeMismatch
  }
}

///|
pub fn Stack::pop_i64(self : Stack) -> Int64 raise RuntimeError {
  match self.pop() {
    I64(n) => n
    _ => raise TypeMismatch
  }
}

///|
pub fn Stack::pop_f32(self : Stack) -> Float raise RuntimeError {
  match self.pop() {
    F32(f) => f
    _ => raise TypeMismatch
  }
}

///|
pub fn Stack::pop_f64(self : Stack) -> Double raise RuntimeError {
  match self.pop() {
    F64(f) => f
    _ => raise TypeMismatch
  }
}

///|
pub fn Stack::size(self : Stack) -> Int {
  self.sp
}

///|
pub fn Stack::clear(self : Stack) -> Unit {
  self.sp = 0
}
