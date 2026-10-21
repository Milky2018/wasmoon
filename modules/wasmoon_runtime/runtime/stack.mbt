///|
/// @types.Value stack for operands
struct Stack {
  values : Array[@types.Value]
  limit : Int32
  mut reserved : Int32
  mut sp : Int32 // stack pointer
  byte_limit : Int64?
  mut accounted_bytes : Int64
} derive(Debug)

///|
pub fn Stack::Stack(
  max_values~ : Int32 = 10000,
  max_bytes~ : Int64? = None,
) -> Stack {
  {
    values: [],
    sp: 0,
    limit: max_values,
    reserved: 0,
    byte_limit: max_bytes,
    accounted_bytes: 0L,
  }
}

///|
// Portable logical charges, independent of target ABI and allocator capacity.
// A value slot includes room for a 16-byte SIMD payload. Metadata charges cover
// a function frame (64) and an instruction/control entry plus its label (96).
fn Stack::charge(self : Stack, bytes : Int64) -> Unit raise RuntimeError {
  if self.byte_limit is Some(limit) {
    if bytes > limit - self.accounted_bytes {
      raise InterpreterStackBytesExceeded
    }
    self.accounted_bytes += bytes
  }
}

///|
fn Stack::uncharge(self : Stack, bytes : Int64) -> Unit {
  if self.byte_limit is Some(_) {
    self.accounted_bytes -= bytes
  }
}

///|
/// Admit a function frame and all its local slots before allocating locals.
pub fn Stack::reserve_frame(
  self : Stack,
  locals : Int32,
) -> Unit raise RuntimeError {
  self.reserve(locals)
  errdefer self.release(locals)
  self.charge(64L)
}

///|
pub fn Stack::release_frame(self : Stack, locals : Int32) -> Unit {
  self.release(locals)
  self.uncharge(64L)
}

///|
/// Admit an execution-control entry together with its branch label.
pub fn Stack::reserve_control(self : Stack) -> Unit raise RuntimeError {
  self.charge(96L)
}

///|
pub fn Stack::release_control(self : Stack) -> Unit {
  self.uncharge(96L)
}

///|
pub fn Stack::push(
  self : Stack,
  value : @types.Value,
) -> Unit raise RuntimeError {
  if self.sp >= self.limit - self.reserved {
    raise StackOverflow
  }
  self.charge(32L)
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
  self.uncharge(32L)
  let value = self.values[self.sp]
  self.values[self.sp] = I32(0)
  value
}

///|
pub fn Stack::peek(self : Stack) -> @types.Value raise RuntimeError {
  if self.sp <= 0 {
    raise StackUnderflow
  }
  self.values[self.sp - 1]
}

///|
pub fn Stack::pop_i32(self : Stack) -> Int32 raise RuntimeError {
  match self.pop() {
    I32(n) => n
    v => {
      @logger.debug("type mismatch: expected i32, got \{v}")
      raise TypeMismatch
    }
  }
}

///|
pub fn Stack::pop_i64(self : Stack) -> Int64 raise RuntimeError {
  match self.pop() {
    I64(n) => n
    v => {
      @logger.debug("type mismatch: expected i64, got \{v}")
      raise TypeMismatch
    }
  }
}

///|
pub fn Stack::pop_f32(self : Stack) -> Float raise RuntimeError {
  match self.pop() {
    F32(f) => f
    v => {
      @logger.debug("type mismatch: expected f32, got \{v}")
      raise TypeMismatch
    }
  }
}

///|
pub fn Stack::pop_f64(self : Stack) -> Double raise RuntimeError {
  match self.pop() {
    F64(f) => f
    v => {
      @logger.debug("type mismatch: expected f64, got \{v}")
      raise TypeMismatch
    }
  }
}

///|
pub fn Stack::push_v128(self : Stack, v : Bytes) -> Unit raise RuntimeError {
  self.push(V128(v))
}

///|
pub fn Stack::pop_v128(self : Stack) -> Bytes raise RuntimeError {
  match self.pop() {
    V128(v) => v
    v => {
      @logger.debug("type mismatch: expected v128, got \{v}")
      raise TypeMismatch
    }
  }
}

///|
pub fn Stack::size(self : Stack) -> Int32 {
  self.sp
}

///|
/// Snapshot currently live stack values [0, sp)
pub fn Stack::active_values(self : Stack) -> Array[@types.Value] {
  let active : Array[@types.Value] = []
  for i in 0..<self.sp {
    active.push(self.values[i])
  }
  active
}

///|
pub fn Stack::clear(self : Stack) -> Unit {
  self.sp = 0
  self.reserved = 0
  self.accounted_bytes = 0L
  self.values.clear()
}

///|
/// Pop n values from the stack, returning them in order (first popped is last in array)
pub fn Stack::pop_n(
  self : Stack,
  n : Int32,
) -> Array[@types.Value] raise RuntimeError {
  if n <= 0 {
    return []
  }
  if self.sp < n {
    raise StackUnderflow
  }
  self.uncharge(n.to_int64() * 32L)
  let values : Array[@types.Value] = Array::make(n, I32(0))
  // Pop in reverse order so the array maintains stack order
  for i = n - 1; i >= 0; i = i - 1 {
    self.sp = self.sp - 1
    values[i] = self.values[self.sp]
    self.values[self.sp] = I32(0)
  }
  values
}

///|
/// Count frame locals against the same budget as live operand slots.
pub fn Stack::reserve(self : Stack, count : Int32) -> Unit raise RuntimeError {
  if count < 0 || count > self.limit - self.reserved - self.sp {
    raise StackOverflow
  }
  self.charge(count.to_int64() * 32L)
  self.reserved += count
}

///|
pub fn Stack::release(self : Stack, count : Int32) -> Unit {
  self.reserved -= count
  self.uncharge(count.to_int64() * 32L)
}
