// Numeric Instructions - i32/i64/f32/f64 arithmetic, comparison, and bitwise operations

///|
/// Execute i32 numeric instruction
fn ExecContext::exec_i32_numeric(
  self : ExecContext,
  instr : @types.Instruction,
) -> Unit raise {
  match instr {
    // i32 arithmetic operations
    I32Add => {
      let b = self.stack.pop_i32()
      let a = self.stack.pop_i32()
      self.stack.push(I32(a + b))
    }
    I32Sub => {
      let b = self.stack.pop_i32()
      let a = self.stack.pop_i32()
      self.stack.push(I32(a - b))
    }
    I32Mul => {
      let b = self.stack.pop_i32()
      let a = self.stack.pop_i32()
      self.stack.push(I32(a * b))
    }
    I32DivS => {
      let b = self.stack.pop_i32()
      let a = self.stack.pop_i32()
      if b == 0 {
        raise @runtime.DivisionByZero
      }
      // Check for integer overflow: INT32_MIN / -1 would overflow
      if a == -2147483648 && b == -1 {
        raise @runtime.IntegerOverflow
      }
      self.stack.push(I32(a / b))
    }
    I32DivU => {
      let b = self.stack.pop_i32()
      let a = self.stack.pop_i32()
      if b == 0 {
        raise @runtime.DivisionByZero
      }
      let result = (a.reinterpret_as_uint() / b.reinterpret_as_uint())
        |> UInt::reinterpret_as_int
      self.stack.push(I32(result))
    }
    I32RemS => {
      let b = self.stack.pop_i32()
      let a = self.stack.pop_i32()
      if b == 0 {
        raise @runtime.DivisionByZero
      }
      self.stack.push(I32(a % b))
    }
    I32RemU => {
      let b = self.stack.pop_i32()
      let a = self.stack.pop_i32()
      if b == 0 {
        raise @runtime.DivisionByZero
      }
      let result = (a.reinterpret_as_uint() % b.reinterpret_as_uint())
        |> UInt::reinterpret_as_int
      self.stack.push(I32(result))
    }
    // i32 comparison operations
    I32Eq => {
      let b = self.stack.pop_i32()
      let a = self.stack.pop_i32()
      self.stack.push(I32(if a == b { 1 } else { 0 }))
    }
    I32Ne => {
      let b = self.stack.pop_i32()
      let a = self.stack.pop_i32()
      self.stack.push(I32(if a != b { 1 } else { 0 }))
    }
    I32LtS => {
      let b = self.stack.pop_i32()
      let a = self.stack.pop_i32()
      self.stack.push(I32(if a < b { 1 } else { 0 }))
    }
    I32GtS => {
      let b = self.stack.pop_i32()
      let a = self.stack.pop_i32()
      self.stack.push(I32(if a > b { 1 } else { 0 }))
    }
    I32LeS => {
      let b = self.stack.pop_i32()
      let a = self.stack.pop_i32()
      self.stack.push(I32(if a <= b { 1 } else { 0 }))
    }
    I32GeS => {
      let b = self.stack.pop_i32()
      let a = self.stack.pop_i32()
      self.stack.push(I32(if a >= b { 1 } else { 0 }))
    }
    I32Eqz => {
      let a = self.stack.pop_i32()
      self.stack.push(I32(if a == 0 { 1 } else { 0 }))
    }
    // i32 bitwise operations
    I32And => {
      let b = self.stack.pop_i32()
      let a = self.stack.pop_i32()
      self.stack.push(I32(a & b))
    }
    I32Or => {
      let b = self.stack.pop_i32()
      let a = self.stack.pop_i32()
      self.stack.push(I32(a | b))
    }
    I32Xor => {
      let b = self.stack.pop_i32()
      let a = self.stack.pop_i32()
      self.stack.push(I32(a ^ b))
    }
    I32Shl => {
      let b = self.stack.pop_i32()
      let a = self.stack.pop_i32()
      self.stack.push(I32(a << (b % 32)))
    }
    I32ShrS => {
      let b = self.stack.pop_i32()
      let a = self.stack.pop_i32()
      self.stack.push(I32(a >> (b % 32)))
    }
    I32ShrU => {
      let b = self.stack.pop_i32()
      let a = self.stack.pop_i32()
      let shift = b % 32
      let result = (a.reinterpret_as_uint() >> shift)
        |> UInt::reinterpret_as_int
      self.stack.push(I32(result))
    }
    I32Rotl => {
      let b = self.stack.pop_i32()
      let a = self.stack.pop_i32()
      let k = b % 32
      // rotl(a, k) = (a << k) | (a >> (32 - k))
      let au = a.reinterpret_as_uint()
      let result = if k == 0 { au } else { (au << k) | (au >> (32 - k)) }
      self.stack.push(I32(result.reinterpret_as_int()))
    }
    I32Rotr => {
      let b = self.stack.pop_i32()
      let a = self.stack.pop_i32()
      let k = b % 32
      // rotr(a, k) = (a >> k) | (a << (32 - k))
      let au = a.reinterpret_as_uint()
      let result = if k == 0 { au } else { (au >> k) | (au << (32 - k)) }
      self.stack.push(I32(result.reinterpret_as_int()))
    }
    I32Clz => {
      let a = self.stack.pop_i32()
      // Count leading zeros
      let au = a.reinterpret_as_uint()
      let count = au.clz()
      self.stack.push(I32(count))
    }
    I32Ctz => {
      let a = self.stack.pop_i32()
      // Count trailing zeros
      let au = a.reinterpret_as_uint()
      let count = au.ctz()
      self.stack.push(I32(count))
    }
    I32Popcnt => {
      let a = self.stack.pop_i32()
      // Count number of 1 bits
      let au = a.reinterpret_as_uint()
      let count = au.popcnt()
      self.stack.push(I32(count))
    }
    // i32 unsigned comparison operations
    I32LtU => {
      let b = self.stack.pop_i32()
      let a = self.stack.pop_i32()
      let result = if a.reinterpret_as_uint() < b.reinterpret_as_uint() {
        1
      } else {
        0
      }
      self.stack.push(I32(result))
    }
    I32GtU => {
      let b = self.stack.pop_i32()
      let a = self.stack.pop_i32()
      let result = if a.reinterpret_as_uint() > b.reinterpret_as_uint() {
        1
      } else {
        0
      }
      self.stack.push(I32(result))
    }
    I32LeU => {
      let b = self.stack.pop_i32()
      let a = self.stack.pop_i32()
      let result = if a.reinterpret_as_uint() <= b.reinterpret_as_uint() {
        1
      } else {
        0
      }
      self.stack.push(I32(result))
    }
    I32GeU => {
      let b = self.stack.pop_i32()
      let a = self.stack.pop_i32()
      let result = if a.reinterpret_as_uint() >= b.reinterpret_as_uint() {
        1
      } else {
        0
      }
      self.stack.push(I32(result))
    }
    // Sign-extension operators
    I32Extend8S => {
      let a = self.stack.pop_i32()
      // Sign-extend from 8 bits to 32 bits
      let result = a << 24 >> 24
      self.stack.push(I32(result))
    }
    I32Extend16S => {
      let a = self.stack.pop_i32()
      // Sign-extend from 16 bits to 32 bits
      let result = a << 16 >> 16
      self.stack.push(I32(result))
    }
    _ => raise @runtime.RuntimeError::Unreachable
  }
}

///|
/// Execute i64 numeric instruction
fn ExecContext::exec_i64_numeric(
  self : ExecContext,
  instr : @types.Instruction,
) -> Unit raise {
  match instr {
    // i64 arithmetic operations
    I64Add => {
      let b = self.stack.pop_i64()
      let a = self.stack.pop_i64()
      self.stack.push(I64(a + b))
    }
    I64Sub => {
      let b = self.stack.pop_i64()
      let a = self.stack.pop_i64()
      self.stack.push(I64(a - b))
    }
    I64Mul => {
      let b = self.stack.pop_i64()
      let a = self.stack.pop_i64()
      self.stack.push(I64(a * b))
    }
    I64DivS => {
      let b = self.stack.pop_i64()
      let a = self.stack.pop_i64()
      if b == 0L {
        raise @runtime.DivisionByZero
      }
      // Check for integer overflow: INT64_MIN / -1 would overflow
      if a == -9223372036854775808L && b == -1L {
        raise @runtime.IntegerOverflow
      }
      self.stack.push(I64(a / b))
    }
    I64DivU => {
      let b = self.stack.pop_i64()
      let a = self.stack.pop_i64()
      if b == 0L {
        raise @runtime.DivisionByZero
      }
      let result = (Int64::reinterpret_as_uint64(a) /
        Int64::reinterpret_as_uint64(b))
        |> UInt64::reinterpret_as_int64
      self.stack.push(I64(result))
    }
    I64RemS => {
      let b = self.stack.pop_i64()
      let a = self.stack.pop_i64()
      if b == 0L {
        raise @runtime.DivisionByZero
      }
      self.stack.push(I64(a % b))
    }
    I64RemU => {
      let b = self.stack.pop_i64()
      let a = self.stack.pop_i64()
      if b == 0L {
        raise @runtime.DivisionByZero
      }
      let result = (Int64::reinterpret_as_uint64(a) %
        Int64::reinterpret_as_uint64(b))
        |> UInt64::reinterpret_as_int64
      self.stack.push(I64(result))
    }
    // i64 comparison operations
    I64Eq => {
      let b = self.stack.pop_i64()
      let a = self.stack.pop_i64()
      self.stack.push(I32(if a == b { 1 } else { 0 }))
    }
    I64Ne => {
      let b = self.stack.pop_i64()
      let a = self.stack.pop_i64()
      self.stack.push(I32(if a != b { 1 } else { 0 }))
    }
    I64LtS => {
      let b = self.stack.pop_i64()
      let a = self.stack.pop_i64()
      self.stack.push(I32(if a < b { 1 } else { 0 }))
    }
    I64GtS => {
      let b = self.stack.pop_i64()
      let a = self.stack.pop_i64()
      self.stack.push(I32(if a > b { 1 } else { 0 }))
    }
    I64LeS => {
      let b = self.stack.pop_i64()
      let a = self.stack.pop_i64()
      self.stack.push(I32(if a <= b { 1 } else { 0 }))
    }
    I64GeS => {
      let b = self.stack.pop_i64()
      let a = self.stack.pop_i64()
      self.stack.push(I32(if a >= b { 1 } else { 0 }))
    }
    I64Eqz => {
      let a = self.stack.pop_i64()
      self.stack.push(I32(if a == 0L { 1 } else { 0 }))
    }
    // i64 bitwise operations
    I64And => {
      let b = self.stack.pop_i64()
      let a = self.stack.pop_i64()
      self.stack.push(I64(a & b))
    }
    I64Or => {
      let b = self.stack.pop_i64()
      let a = self.stack.pop_i64()
      self.stack.push(I64(a | b))
    }
    I64Xor => {
      let b = self.stack.pop_i64()
      let a = self.stack.pop_i64()
      self.stack.push(I64(a ^ b))
    }
    I64Shl => {
      let b = self.stack.pop_i64()
      let a = self.stack.pop_i64()
      self.stack.push(I64(a << (b.to_int() % 64)))
    }
    I64ShrS => {
      let b = self.stack.pop_i64()
      let a = self.stack.pop_i64()
      self.stack.push(I64(a >> (b.to_int() % 64)))
    }
    I64ShrU => {
      let b = self.stack.pop_i64()
      let a = self.stack.pop_i64()
      let shift = b.to_int() % 64
      let result = (Int64::reinterpret_as_uint64(a) >> shift)
        |> UInt64::reinterpret_as_int64
      self.stack.push(I64(result))
    }
    I64Rotl => {
      let b = self.stack.pop_i64()
      let a = self.stack.pop_i64()
      let k = b.to_int() % 64
      // rotl(a, k) = (a << k) | (a >> (64 - k))
      let au = Int64::reinterpret_as_uint64(a)
      let result = if k == 0 { au } else { (au << k) | (au >> (64 - k)) }
      self.stack.push(I64(UInt64::reinterpret_as_int64(result)))
    }
    I64Rotr => {
      let b = self.stack.pop_i64()
      let a = self.stack.pop_i64()
      let k = b.to_int() % 64
      // rotr(a, k) = (a >> k) | (a << (64 - k))
      let au = Int64::reinterpret_as_uint64(a)
      let result = if k == 0 { au } else { (au >> k) | (au << (64 - k)) }
      self.stack.push(I64(UInt64::reinterpret_as_int64(result)))
    }
    I64Clz => {
      let a = self.stack.pop_i64()
      // Count leading zeros
      let au = Int64::reinterpret_as_uint64(a)
      let count = au.clz()
      self.stack.push(I64(count.to_int64()))
    }
    I64Ctz => {
      let a = self.stack.pop_i64()
      // Count trailing zeros
      let au = Int64::reinterpret_as_uint64(a)
      let count = au.ctz()
      self.stack.push(I64(count.to_int64()))
    }
    I64Popcnt => {
      let a = self.stack.pop_i64()
      // Count number of 1 bits
      let au = Int64::reinterpret_as_uint64(a)
      let count = au.popcnt()
      self.stack.push(I64(count.to_int64()))
    }
    // i64 unsigned comparison operations
    I64LtU => {
      let b = self.stack.pop_i64()
      let a = self.stack.pop_i64()
      let result = if Int64::reinterpret_as_uint64(a) <
        Int64::reinterpret_as_uint64(b) {
        1
      } else {
        0
      }
      self.stack.push(I32(result))
    }
    I64GtU => {
      let b = self.stack.pop_i64()
      let a = self.stack.pop_i64()
      let result = if Int64::reinterpret_as_uint64(a) >
        Int64::reinterpret_as_uint64(b) {
        1
      } else {
        0
      }
      self.stack.push(I32(result))
    }
    I64LeU => {
      let b = self.stack.pop_i64()
      let a = self.stack.pop_i64()
      let result = if Int64::reinterpret_as_uint64(a) <=
        Int64::reinterpret_as_uint64(b) {
        1
      } else {
        0
      }
      self.stack.push(I32(result))
    }
    I64GeU => {
      let b = self.stack.pop_i64()
      let a = self.stack.pop_i64()
      let result = if Int64::reinterpret_as_uint64(a) >=
        Int64::reinterpret_as_uint64(b) {
        1
      } else {
        0
      }
      self.stack.push(I32(result))
    }
    // Sign-extension operators
    I64Extend8S => {
      let a = self.stack.pop_i64()
      // Sign-extend from 8 bits to 64 bits
      let result = a << 56 >> 56
      self.stack.push(I64(result))
    }
    I64Extend16S => {
      let a = self.stack.pop_i64()
      // Sign-extend from 16 bits to 64 bits
      let result = a << 48 >> 48
      self.stack.push(I64(result))
    }
    I64Extend32S => {
      let a = self.stack.pop_i64()
      // Sign-extend from 32 bits to 64 bits
      let result = a << 32 >> 32
      self.stack.push(I64(result))
    }
    _ => raise @runtime.RuntimeError::Unreachable
  }
}

///|
/// Execute f32 numeric instruction
fn ExecContext::exec_f32_numeric(
  self : ExecContext,
  instr : @types.Instruction,
) -> Unit raise {
  match instr {
    // f32 arithmetic operations
    F32Add => {
      let b = self.stack.pop_f32()
      let a = self.stack.pop_f32()
      self.stack.push(F32(a + b))
    }
    F32Sub => {
      let b = self.stack.pop_f32()
      let a = self.stack.pop_f32()
      self.stack.push(F32(a - b))
    }
    F32Mul => {
      let b = self.stack.pop_f32()
      let a = self.stack.pop_f32()
      self.stack.push(F32(a * b))
    }
    F32Div => {
      let b = self.stack.pop_f32()
      let a = self.stack.pop_f32()
      self.stack.push(F32(a / b))
    }
    F32Abs => {
      let a = self.stack.pop_f32()
      self.stack.push(F32(a.abs()))
    }
    F32Neg => {
      let a = self.stack.pop_f32()
      self.stack.push(F32(-a))
    }
    F32Sqrt => {
      let a = self.stack.pop_f32()
      self.stack.push(F32(a.sqrt()))
    }
    F32Ceil => {
      let a = self.stack.pop_f32()
      self.stack.push(F32(a.ceil()))
    }
    F32Floor => {
      let a = self.stack.pop_f32()
      self.stack.push(F32(a.floor()))
    }
    F32Trunc => {
      let a = self.stack.pop_f32()
      self.stack.push(F32(a.trunc()))
    }
    F32Nearest => {
      let a = self.stack.pop_f32()
      // Round to nearest even (banker's rounding)
      self.stack.push(F32(a.round()))
    }
    F32Min => {
      let b = self.stack.pop_f32()
      let a = self.stack.pop_f32()
      // Per WASM spec: if either operand is NaN, return NaN
      let result : Float = if a.is_nan() || b.is_nan() {
        (0.0 : Float) / (0.0 : Float) // NaN
      } else if a == (0.0 : Float) && b == (0.0 : Float) {
        // Handle -0.0 vs +0.0: min(-0.0, +0.0) = -0.0
        if a.reinterpret_as_uint() > b.reinterpret_as_uint() { a } else { b }
      } else if a < b {
        a
      } else {
        b
      }
      self.stack.push(F32(result))
    }
    F32Max => {
      let b = self.stack.pop_f32()
      let a = self.stack.pop_f32()
      // Per WASM spec: if either operand is NaN, return NaN
      let result : Float = if a.is_nan() || b.is_nan() {
        (0.0 : Float) / (0.0 : Float) // NaN
      } else if a == (0.0 : Float) && b == (0.0 : Float) {
        // Handle -0.0 vs +0.0: max(-0.0, +0.0) = +0.0
        if a.reinterpret_as_uint() < b.reinterpret_as_uint() { a } else { b }
      } else if a > b {
        a
      } else {
        b
      }
      self.stack.push(F32(result))
    }
    // f32 comparison operations
    F32Eq => {
      let b = self.stack.pop_f32()
      let a = self.stack.pop_f32()
      self.stack.push(I32(if a == b { 1 } else { 0 }))
    }
    F32Ne => {
      let b = self.stack.pop_f32()
      let a = self.stack.pop_f32()
      self.stack.push(I32(if a != b { 1 } else { 0 }))
    }
    F32Lt => {
      let b = self.stack.pop_f32()
      let a = self.stack.pop_f32()
      self.stack.push(I32(if a < b { 1 } else { 0 }))
    }
    F32Gt => {
      let b = self.stack.pop_f32()
      let a = self.stack.pop_f32()
      self.stack.push(I32(if a > b { 1 } else { 0 }))
    }
    F32Le => {
      let b = self.stack.pop_f32()
      let a = self.stack.pop_f32()
      self.stack.push(I32(if a <= b { 1 } else { 0 }))
    }
    F32Ge => {
      let b = self.stack.pop_f32()
      let a = self.stack.pop_f32()
      self.stack.push(I32(if a >= b { 1 } else { 0 }))
    }
    _ => raise @runtime.RuntimeError::Unreachable
  }
}

///|
/// Execute f64 numeric instruction
fn ExecContext::exec_f64_numeric(
  self : ExecContext,
  instr : @types.Instruction,
) -> Unit raise {
  match instr {
    // f64 arithmetic operations
    F64Add => {
      let b = self.stack.pop_f64()
      let a = self.stack.pop_f64()
      self.stack.push(F64(a + b))
    }
    F64Sub => {
      let b = self.stack.pop_f64()
      let a = self.stack.pop_f64()
      self.stack.push(F64(a - b))
    }
    F64Mul => {
      let b = self.stack.pop_f64()
      let a = self.stack.pop_f64()
      self.stack.push(F64(a * b))
    }
    F64Div => {
      let b = self.stack.pop_f64()
      let a = self.stack.pop_f64()
      self.stack.push(F64(a / b))
    }
    F64Abs => {
      let a = self.stack.pop_f64()
      self.stack.push(F64(a.abs()))
    }
    F64Neg => {
      let a = self.stack.pop_f64()
      self.stack.push(F64(-a))
    }
    F64Sqrt => {
      let a = self.stack.pop_f64()
      self.stack.push(F64(a.sqrt()))
    }
    F64Ceil => {
      let a = self.stack.pop_f64()
      self.stack.push(F64(a.ceil()))
    }
    F64Floor => {
      let a = self.stack.pop_f64()
      self.stack.push(F64(a.floor()))
    }
    F64Trunc => {
      let a = self.stack.pop_f64()
      self.stack.push(F64(a.trunc()))
    }
    F64Nearest => {
      let a = self.stack.pop_f64()
      // Round to nearest even (banker's rounding)
      self.stack.push(F64(a.round()))
    }
    F64Min => {
      let b = self.stack.pop_f64()
      let a = self.stack.pop_f64()
      // Per WASM spec: if either operand is NaN, return NaN
      let result = if a.is_nan() || b.is_nan() {
        0.0 / 0.0 // NaN
      } else if a == 0.0 && b == 0.0 {
        // Handle -0.0 vs +0.0: min(-0.0, +0.0) = -0.0
        if a.reinterpret_as_uint64() > b.reinterpret_as_uint64() { a } else { b }
      } else if a < b {
        a
      } else {
        b
      }
      self.stack.push(F64(result))
    }
    F64Max => {
      let b = self.stack.pop_f64()
      let a = self.stack.pop_f64()
      // Per WASM spec: if either operand is NaN, return NaN
      let result = if a.is_nan() || b.is_nan() {
        0.0 / 0.0 // NaN
      } else if a == 0.0 && b == 0.0 {
        // Handle -0.0 vs +0.0: max(-0.0, +0.0) = +0.0
        if a.reinterpret_as_uint64() < b.reinterpret_as_uint64() { a } else { b }
      } else if a > b {
        a
      } else {
        b
      }
      self.stack.push(F64(result))
    }
    // f64 comparison operations
    F64Eq => {
      let b = self.stack.pop_f64()
      let a = self.stack.pop_f64()
      self.stack.push(I32(if a == b { 1 } else { 0 }))
    }
    F64Ne => {
      let b = self.stack.pop_f64()
      let a = self.stack.pop_f64()
      self.stack.push(I32(if a != b { 1 } else { 0 }))
    }
    F64Lt => {
      let b = self.stack.pop_f64()
      let a = self.stack.pop_f64()
      self.stack.push(I32(if a < b { 1 } else { 0 }))
    }
    F64Gt => {
      let b = self.stack.pop_f64()
      let a = self.stack.pop_f64()
      self.stack.push(I32(if a > b { 1 } else { 0 }))
    }
    F64Le => {
      let b = self.stack.pop_f64()
      let a = self.stack.pop_f64()
      self.stack.push(I32(if a <= b { 1 } else { 0 }))
    }
    F64Ge => {
      let b = self.stack.pop_f64()
      let a = self.stack.pop_f64()
      self.stack.push(I32(if a >= b { 1 } else { 0 }))
    }
    _ => raise @runtime.RuntimeError::Unreachable
  }
}
