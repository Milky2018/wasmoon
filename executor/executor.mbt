// Wasmoon Executor - MVP execution engine
// Simple interpreter for basic WASM instructions

// ============================================================
// Execution Context
// ============================================================

///|
/// Execution context for running WASM code
struct ExecContext {
  stack : @runtime.Stack
  store : @runtime.Store
  frames : Array[@runtime.Frame]
  mut current_frame : Int
} derive(Show)

///|
fn ExecContext::new(store : @runtime.Store) -> ExecContext {
  { stack: @runtime.Stack::new(), store, frames: [], current_frame: 0 }
}

///|
fn ExecContext::push_frame(self : ExecContext, frame : @runtime.Frame) -> Unit {
  self.frames.push(frame)
  self.current_frame = self.frames.length() - 1
}

///|
fn ExecContext::pop_frame(
  self : ExecContext,
) -> Unit raise @runtime.RuntimeError {
  if self.frames.length() == 0 {
    raise @runtime.CallStackExhausted
  }
  let _ = self.frames.pop()
  self.current_frame = self.frames.length() - 1
}

///|
fn ExecContext::get_frame(
  self : ExecContext,
) -> @runtime.Frame raise @runtime.RuntimeError {
  if self.current_frame < 0 || self.current_frame >= self.frames.length() {
    raise @runtime.CallStackExhausted
  }
  self.frames[self.current_frame]
}

// ============================================================
// @wasmoon.Instruction Execution
// ============================================================

///|
/// Execute a single instruction
fn ExecContext::exec_instr(
  self : ExecContext,
  instr : @wasmoon.Instruction,
) -> Unit raise {
  match instr {
    // Constants
    I32Const(n) => self.stack.push(I32(n))
    I64Const(n) => self.stack.push(I64(n))
    F32Const(f) => self.stack.push(F32(f))
    F64Const(d) => self.stack.push(F64(d))

    // Local variables
    LocalGet(idx) => {
      let frame = self.get_frame()
      let value = frame.get_local(idx)
      self.stack.push(value)
    }
    LocalSet(idx) => {
      let value = self.stack.pop()
      let frame = self.get_frame()
      frame.set_local(idx, value)
    }
    LocalTee(idx) => {
      let value = self.stack.peek()
      let frame = self.get_frame()
      frame.set_local(idx, value)
    }

    // Drop
    Drop => {
      let _ = self.stack.pop()

    }

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
      self.stack.push(I32(a / b))
    }
    I32DivU => {
      let b = self.stack.pop_i32()
      let a = self.stack.pop_i32()
      if b == 0 {
        raise @runtime.DivisionByZero
      }
      // Unsigned division: reinterpret as UInt
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
      // Unsigned remainder: reinterpret as UInt
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
      // Unsigned right shift: reinterpret as UInt
      let result = (a.reinterpret_as_uint() >> shift)
        |> UInt::reinterpret_as_int
      self.stack.push(I32(result))
    }

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
      self.stack.push(I64(a / b))
    }
    I64DivU => {
      let b = self.stack.pop_i64()
      let a = self.stack.pop_i64()
      if b == 0L {
        raise @runtime.DivisionByZero
      }
      // Unsigned division: reinterpret as UInt64
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
      // Unsigned remainder: reinterpret as UInt64
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
      // Unsigned right shift: reinterpret as UInt64
      let result = (Int64::reinterpret_as_uint64(a) >> shift)
        |> UInt64::reinterpret_as_int64
      self.stack.push(I64(result))
    }

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
    F32Min => {
      let b = self.stack.pop_f32()
      let a = self.stack.pop_f32()
      self.stack.push(F32(if a < b { a } else { b }))
    }
    F32Max => {
      let b = self.stack.pop_f32()
      let a = self.stack.pop_f32()
      self.stack.push(F32(if a > b { a } else { b }))
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
    F64Min => {
      let b = self.stack.pop_f64()
      let a = self.stack.pop_f64()
      self.stack.push(F64(if a < b { a } else { b }))
    }
    F64Max => {
      let b = self.stack.pop_f64()
      let a = self.stack.pop_f64()
      self.stack.push(F64(if a > b { a } else { b }))
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

    // ============================================================
    // Numeric Conversion Instructions
    // ============================================================

    // i32.wrap_i64: i64 -> i32 (取低32位)
    I32WrapI64 => {
      let a = self.stack.pop_i64()
      self.stack.push(I32(a.to_int()))
    }

    // i64.extend_i32_s: i32 -> i64 (有符号扩展)
    I64ExtendI32S => {
      let a = self.stack.pop_i32()
      self.stack.push(I64(a.to_int64()))
    }

    // i64.extend_i32_u: i32 -> i64 (无符号扩展)
    I64ExtendI32U => {
      let a = self.stack.pop_i32()
      self.stack.push(I64(a.to_uint64().reinterpret_as_int64()))
    }

    // i32.trunc_f32_s: f32 -> i32 (有符号截断)
    I32TruncF32S => {
      let a = self.stack.pop_f32()
      self.stack.push(I32(a.to_int()))
    }

    // i32.trunc_f32_u: f32 -> i32 (无符号截断)
    I32TruncF32U => {
      let a = self.stack.pop_f32()
      self.stack.push(I32(a.to_double().to_uint().reinterpret_as_int()))
    }

    // i32.trunc_f64_s: f64 -> i32 (有符号截断)
    I32TruncF64S => {
      let a = self.stack.pop_f64()
      self.stack.push(I32(a.to_int()))
    }

    // i32.trunc_f64_u: f64 -> i32 (无符号截断)
    I32TruncF64U => {
      let a = self.stack.pop_f64()
      self.stack.push(I32(a.to_uint().reinterpret_as_int()))
    }

    // i64.trunc_f32_s: f32 -> i64 (有符号截断)
    I64TruncF32S => {
      let a = self.stack.pop_f32()
      self.stack.push(I64(a.to_double().to_int64()))
    }

    // i64.trunc_f32_u: f32 -> i64 (无符号截断)
    I64TruncF32U => {
      let a = self.stack.pop_f32()
      self.stack.push(I64(a.to_double().to_uint64().reinterpret_as_int64()))
    }

    // i64.trunc_f64_s: f64 -> i64 (有符号截断)
    I64TruncF64S => {
      let a = self.stack.pop_f64()
      self.stack.push(I64(a.to_int64()))
    }

    // i64.trunc_f64_u: f64 -> i64 (无符号截断)
    I64TruncF64U => {
      let a = self.stack.pop_f64()
      self.stack.push(I64(a.to_uint64().reinterpret_as_int64()))
    }

    // f32.convert_i32_s: i32 -> f32 (有符号转换)
    F32ConvertI32S => {
      let a = self.stack.pop_i32()
      self.stack.push(F32(a.to_float()))
    }

    // f32.convert_i32_u: i32 -> f32 (无符号转换)
    F32ConvertI32U => {
      let a = self.stack.pop_i32()
      self.stack.push(F32(a.reinterpret_as_uint().to_float()))
    }

    // f32.convert_i64_s: i64 -> f32 (有符号转换)
    F32ConvertI64S => {
      let a = self.stack.pop_i64()
      self.stack.push(F32(a.to_float()))
    }

    // f32.convert_i64_u: i64 -> f32 (无符号转换)
    F32ConvertI64U => {
      let a = self.stack.pop_i64()
      self.stack.push(F32(a.reinterpret_as_uint64().to_float()))
    }

    // f64.convert_i32_s: i32 -> f64 (有符号转换)
    F64ConvertI32S => {
      let a = self.stack.pop_i32()
      self.stack.push(F64(a.to_double()))
    }

    // f64.convert_i32_u: i32 -> f64 (无符号转换)
    F64ConvertI32U => {
      let a = self.stack.pop_i32()
      self.stack.push(F64(a.reinterpret_as_uint().to_double()))
    }

    // f64.convert_i64_s: i64 -> f64 (有符号转换)
    F64ConvertI64S => {
      let a = self.stack.pop_i64()
      self.stack.push(F64(a.to_double()))
    }

    // f64.convert_i64_u: i64 -> f64 (无符号转换)
    F64ConvertI64U => {
      let a = self.stack.pop_i64()
      let unsigned = a.reinterpret_as_uint64()
      self.stack.push(F64(unsigned.to_double()))
    }

    // f32.demote_f64: f64 -> f32
    F32DemoteF64 => {
      let a = self.stack.pop_f64()
      self.stack.push(F32(a.to_float()))
    }

    // f64.promote_f32: f32 -> f64
    F64PromoteF32 => {
      let a = self.stack.pop_f32()
      self.stack.push(F64(a.to_double()))
    }

    // i32.reinterpret_f32: f32 的位模式 -> i32
    I32ReinterpretF32 => {
      let a = self.stack.pop_f32()
      self.stack.push(I32(a.reinterpret_as_int()))
    }

    // i64.reinterpret_f64: f64 的位模式 -> i64
    I64ReinterpretF64 => {
      let a = self.stack.pop_f64()
      self.stack.push(I64(a.reinterpret_as_int64()))
    }

    // f32.reinterpret_i32: i32 的位模式 -> f32
    F32ReinterpretI32 => {
      let a = self.stack.pop_i32()
      self.stack.push(F32(a.reinterpret_as_float()))
    }

    // f64.reinterpret_i64: i64 的位模式 -> f64
    F64ReinterpretI64 => {
      let a = self.stack.pop_i64()
      self.stack.push(F64(a.reinterpret_as_double()))
    }

    // ============================================================
    // Saturating Truncation Instructions
    // ============================================================

    // i32.trunc_sat_f32_s: f32 -> i32 (饱和有符号截断)
    I32TruncSatF32S => {
      let a = self.stack.pop_f32()
      let result = if a.is_nan() {
        0
      } else if a >= 2147483647.0 {
        2147483647
      } else if a <= -2147483648.0 {
        -2147483648
      } else {
        a.to_int()
      }
      self.stack.push(I32(result))
    }

    // i32.trunc_sat_f32_u: f32 -> i32 (饱和无符号截断)
    I32TruncSatF32U => {
      let a = self.stack.pop_f32()
      let result = if a.is_nan() || a <= 0.0 {
        0
      } else if a >= 4294967295.0 {
        -1 // 0xFFFFFFFF as signed
      } else {
        a.to_double().to_uint().reinterpret_as_int()
      }
      self.stack.push(I32(result))
    }

    // i32.trunc_sat_f64_s: f64 -> i32 (饱和有符号截断)
    I32TruncSatF64S => {
      let a = self.stack.pop_f64()
      let result = if a.is_nan() {
        0
      } else if a >= 2147483647.0 {
        2147483647
      } else if a <= -2147483648.0 {
        -2147483648
      } else {
        a.to_int()
      }
      self.stack.push(I32(result))
    }

    // i32.trunc_sat_f64_u: f64 -> i32 (饱和无符号截断)
    I32TruncSatF64U => {
      let a = self.stack.pop_f64()
      let result = if a.is_nan() || a <= 0.0 {
        0
      } else if a >= 4294967295.0 {
        -1 // 0xFFFFFFFF as signed
      } else {
        a.to_uint().reinterpret_as_int()
      }
      self.stack.push(I32(result))
    }

    // i64.trunc_sat_f32_s: f32 -> i64 (饱和有符号截断)
    I64TruncSatF32S => {
      let a = self.stack.pop_f32()
      let d = a.to_double()
      let result = if a.is_nan() {
        0L
      } else if d >= 9223372036854775807.0 {
        9223372036854775807L
      } else if d <= -9223372036854775808.0 {
        -9223372036854775808L
      } else {
        d.to_int64()
      }
      self.stack.push(I64(result))
    }

    // i64.trunc_sat_f32_u: f32 -> i64 (饱和无符号截断)
    I64TruncSatF32U => {
      let a = self.stack.pop_f32()
      let d = a.to_double()
      let result = if a.is_nan() || d <= 0.0 {
        0L
      } else if d >= 18446744073709551615.0 {
        -1L // 0xFFFFFFFFFFFFFFFF as signed
      } else {
        d.to_uint64().reinterpret_as_int64()
      }
      self.stack.push(I64(result))
    }

    // i64.trunc_sat_f64_s: f64 -> i64 (饱和有符号截断)
    I64TruncSatF64S => {
      let a = self.stack.pop_f64()
      let result = if a.is_nan() {
        0L
      } else if a >= 9223372036854775807.0 {
        9223372036854775807L
      } else if a <= -9223372036854775808.0 {
        -9223372036854775808L
      } else {
        a.to_int64()
      }
      self.stack.push(I64(result))
    }

    // i64.trunc_sat_f64_u: f64 -> i64 (饱和无符号截断)
    I64TruncSatF64U => {
      let a = self.stack.pop_f64()
      let result = if a.is_nan() || a <= 0.0 {
        0L
      } else if a >= 18446744073709551615.0 {
        -1L // 0xFFFFFFFFFFFFFFFF as signed
      } else {
        a.to_uint64().reinterpret_as_int64()
      }
      self.stack.push(I64(result))
    }

    // ============================================================
    // Memory Load Instructions
    // ============================================================

    // i32.load: load 4 bytes as i32
    I32Load(_align, offset) => {
      let base_addr = self.stack.pop_i32()
      let effective_addr = base_addr + offset
      let mem = self.store.get_mem(0) // Memory index 0 for MVP
      let value = mem.load_i32(effective_addr)
      self.stack.push(I32(value))
    }

    // i64.load: load 8 bytes as i64
    I64Load(_align, offset) => {
      let base_addr = self.stack.pop_i32()
      let effective_addr = base_addr + offset
      let mem = self.store.get_mem(0)
      let value = mem.load_i64(effective_addr)
      self.stack.push(I64(value))
    }

    // f32.load: load 4 bytes as f32
    F32Load(_align, offset) => {
      let base_addr = self.stack.pop_i32()
      let effective_addr = base_addr + offset
      let mem = self.store.get_mem(0)
      let value = mem.load_f32(effective_addr)
      self.stack.push(F32(value))
    }

    // f64.load: load 8 bytes as f64
    F64Load(_align, offset) => {
      let base_addr = self.stack.pop_i32()
      let effective_addr = base_addr + offset
      let mem = self.store.get_mem(0)
      let value = mem.load_f64(effective_addr)
      self.stack.push(F64(value))
    }

    // i32.load8_s: load 1 byte, sign-extend to i32
    I32Load8S(_align, offset) => {
      let base_addr = self.stack.pop_i32()
      let effective_addr = base_addr + offset
      let mem = self.store.get_mem(0)
      let value = mem.load_i32_8s(effective_addr)
      self.stack.push(I32(value))
    }

    // i32.load8_u: load 1 byte, zero-extend to i32
    I32Load8U(_align, offset) => {
      let base_addr = self.stack.pop_i32()
      let effective_addr = base_addr + offset
      let mem = self.store.get_mem(0)
      let value = mem.load_i32_8u(effective_addr)
      self.stack.push(I32(value))
    }

    // i32.load16_s: load 2 bytes, sign-extend to i32
    I32Load16S(_align, offset) => {
      let base_addr = self.stack.pop_i32()
      let effective_addr = base_addr + offset
      let mem = self.store.get_mem(0)
      let value = mem.load_i32_16s(effective_addr)
      self.stack.push(I32(value))
    }

    // i32.load16_u: load 2 bytes, zero-extend to i32
    I32Load16U(_align, offset) => {
      let base_addr = self.stack.pop_i32()
      let effective_addr = base_addr + offset
      let mem = self.store.get_mem(0)
      let value = mem.load_i32_16u(effective_addr)
      self.stack.push(I32(value))
    }

    // i64.load8_s: load 1 byte, sign-extend to i64
    I64Load8S(_align, offset) => {
      let base_addr = self.stack.pop_i32()
      let effective_addr = base_addr + offset
      let mem = self.store.get_mem(0)
      let value = mem.load_i64_8s(effective_addr)
      self.stack.push(I64(value))
    }

    // i64.load8_u: load 1 byte, zero-extend to i64
    I64Load8U(_align, offset) => {
      let base_addr = self.stack.pop_i32()
      let effective_addr = base_addr + offset
      let mem = self.store.get_mem(0)
      let value = mem.load_i64_8u(effective_addr)
      self.stack.push(I64(value))
    }

    // i64.load16_s: load 2 bytes, sign-extend to i64
    I64Load16S(_align, offset) => {
      let base_addr = self.stack.pop_i32()
      let effective_addr = base_addr + offset
      let mem = self.store.get_mem(0)
      let value = mem.load_i64_16s(effective_addr)
      self.stack.push(I64(value))
    }

    // i64.load16_u: load 2 bytes, zero-extend to i64
    I64Load16U(_align, offset) => {
      let base_addr = self.stack.pop_i32()
      let effective_addr = base_addr + offset
      let mem = self.store.get_mem(0)
      let value = mem.load_i64_16u(effective_addr)
      self.stack.push(I64(value))
    }

    // i64.load32_s: load 4 bytes, sign-extend to i64
    I64Load32S(_align, offset) => {
      let base_addr = self.stack.pop_i32()
      let effective_addr = base_addr + offset
      let mem = self.store.get_mem(0)
      let value = mem.load_i64_32s(effective_addr)
      self.stack.push(I64(value))
    }

    // i64.load32_u: load 4 bytes, zero-extend to i64
    I64Load32U(_align, offset) => {
      let base_addr = self.stack.pop_i32()
      let effective_addr = base_addr + offset
      let mem = self.store.get_mem(0)
      let value = mem.load_i64_32u(effective_addr)
      self.stack.push(I64(value))
    }

    // ============================================================
    // Memory Store Instructions
    // ============================================================

    // i32.store: store i32 as 4 bytes
    I32Store(_align, offset) => {
      let value = self.stack.pop_i32()
      let base_addr = self.stack.pop_i32()
      let effective_addr = base_addr + offset
      let mem = self.store.get_mem(0)
      mem.store_i32(effective_addr, value)
    }

    // i64.store: store i64 as 8 bytes
    I64Store(_align, offset) => {
      let value = self.stack.pop_i64()
      let base_addr = self.stack.pop_i32()
      let effective_addr = base_addr + offset
      let mem = self.store.get_mem(0)
      mem.store_i64(effective_addr, value)
    }

    // f32.store: store f32 as 4 bytes
    F32Store(_align, offset) => {
      let value = self.stack.pop_f32()
      let base_addr = self.stack.pop_i32()
      let effective_addr = base_addr + offset
      let mem = self.store.get_mem(0)
      mem.store_f32(effective_addr, value)
    }

    // f64.store: store f64 as 8 bytes
    F64Store(_align, offset) => {
      let value = self.stack.pop_f64()
      let base_addr = self.stack.pop_i32()
      let effective_addr = base_addr + offset
      let mem = self.store.get_mem(0)
      mem.store_f64(effective_addr, value)
    }

    // i32.store8: store low 8 bits of i32
    I32Store8(_align, offset) => {
      let value = self.stack.pop_i32()
      let base_addr = self.stack.pop_i32()
      let effective_addr = base_addr + offset
      let mem = self.store.get_mem(0)
      mem.store_i32_8(effective_addr, value)
    }

    // i32.store16: store low 16 bits of i32
    I32Store16(_align, offset) => {
      let value = self.stack.pop_i32()
      let base_addr = self.stack.pop_i32()
      let effective_addr = base_addr + offset
      let mem = self.store.get_mem(0)
      mem.store_i32_16(effective_addr, value)
    }

    // i64.store8: store low 8 bits of i64
    I64Store8(_align, offset) => {
      let value = self.stack.pop_i64()
      let base_addr = self.stack.pop_i32()
      let effective_addr = base_addr + offset
      let mem = self.store.get_mem(0)
      mem.store_i64_8(effective_addr, value)
    }

    // i64.store16: store low 16 bits of i64
    I64Store16(_align, offset) => {
      let value = self.stack.pop_i64()
      let base_addr = self.stack.pop_i32()
      let effective_addr = base_addr + offset
      let mem = self.store.get_mem(0)
      mem.store_i64_16(effective_addr, value)
    }

    // i64.store32: store low 32 bits of i64
    I64Store32(_align, offset) => {
      let value = self.stack.pop_i64()
      let base_addr = self.stack.pop_i32()
      let effective_addr = base_addr + offset
      let mem = self.store.get_mem(0)
      mem.store_i64_32(effective_addr, value)
    }

    // ============================================================
    // Memory Size and Grow Instructions
    // ============================================================

    // memory.size: return current memory size in pages
    MemorySize => {
      let mem = self.store.get_mem(0)
      self.stack.push(I32(mem.size_pages()))
    }

    // memory.grow: grow memory by delta pages, return old size or -1 on failure
    MemoryGrow => {
      let delta = self.stack.pop_i32()
      let mem = self.store.get_mem(0)
      let result = mem.grow(delta)
      self.stack.push(I32(result))
    }

    // ============================================================
    // Control Flow Instructions
    // ============================================================

    // Block: execute body, br 0 jumps to end
    Block(_bt, body) =>
      self.exec_block(body) catch {
        @runtime.Branch(0) => () // Branch to this block = exit
        @runtime.Branch(n) => raise @runtime.Branch(n - 1) // Propagate
        e => raise e // Re-raise other errors
      }

    // Loop: execute body, br 0 jumps to start
    Loop(_bt, body) =>
      loop () {
        _ =>
          try {
            self.exec_block(body)
            break () // Normal exit
          } catch {
            @runtime.Branch(0) => continue () // Restart loop
            @runtime.Branch(n) => raise @runtime.Branch(n - 1)
            e => raise e
          }
      }

    // If-else: pop condition, execute appropriate branch
    If(_bt, then_body, else_body) => {
      let cond = self.stack.pop_i32()
      let body = if cond != 0 { then_body } else { else_body }
      self.exec_block(body) catch {
        @runtime.Branch(0) => () // Branch to this if = exit
        @runtime.Branch(n) => raise @runtime.Branch(n - 1)
        e => raise e
      }
    }

    // Unconditional branch
    Br(depth) => raise @runtime.Branch(depth)

    // Conditional branch
    BrIf(depth) => {
      let cond = self.stack.pop_i32()
      if cond != 0 {
        raise @runtime.Branch(depth)
      }
    }

    // Table-driven branch
    BrTable(labels, default) => {
      let idx = self.stack.pop_i32()
      let depth = if idx >= 0 && idx < labels.length() {
        labels[idx]
      } else {
        default
      }
      raise @runtime.Branch(depth)
    }

    // Unreachable trap
    Unreachable => raise @runtime.RuntimeError::Unreachable

    // Select: ternary operator
    Select => {
      let cond = self.stack.pop_i32()
      let val2 = self.stack.pop()
      let val1 = self.stack.pop()
      self.stack.push(if cond != 0 { val1 } else { val2 })
    }
    Nop => ()
    Return => raise @runtime.Return
    _ => raise @runtime.RuntimeError::Unreachable
  }
}

///|
/// Execute a block body (can raise ControlSignal)
fn ExecContext::exec_block(
  self : ExecContext,
  instrs : Array[@wasmoon.Instruction],
) -> Unit raise {
  for instr in instrs {
    self.exec_instr(instr)
  }
}

///|
/// Execute function body (catches Return signal)
fn ExecContext::exec_expr(
  self : ExecContext,
  instrs : Array[@wasmoon.Instruction],
) -> Unit raise {
  self.exec_block(instrs) catch {
    @runtime.Return => () // Normal function return
    e => raise e
  }
}

// ============================================================
// Function Execution
// ============================================================

///|
/// Call a function by index
pub fn ExecContext::call_func(
  self : ExecContext,
  func_idx : Int,
  args : Array[@wasmoon.Value],
) -> Array[@wasmoon.Value] raise {
  let func = self.store.get_func(func_idx)

  // Create locals array: params + local variables
  let locals : Array[@wasmoon.Value] = []

  // Add parameters
  for arg in args {
    locals.push(arg)
  }

  // Add local variables (initialized to 0/null)
  for local_type in func.locals {
    locals.push(
      match local_type {
        I32 => I32(0)
        I64 => I64(0L)
        F32 => F32(0.0)
        F64 => F64(0.0)
        FuncRef => Null
        ExternRef => Null
        _ => Null
      },
    )
  }

  // Create and push frame
  let frame = @runtime.Frame::new(func_idx, locals, 1) // Assume single return value for MVP
  self.push_frame(frame)

  // Execute function body
  self.exec_expr(func.body)

  // Pop frame
  self.pop_frame()

  // Collect return values from stack
  let results : Array[@wasmoon.Value] = []
  if self.stack.size() > 0 {
    results.push(self.stack.pop())
  }
  results
}

// ============================================================
// Module Instantiation (MVP)
// ============================================================

///|
/// Create a simple module instance from a parsed module
pub fn instantiate_module(
  mod : @wasmoon.Module,
) -> (@runtime.Store, @runtime.ModuleInstance) {
  let store = @runtime.Store::new()

  // Allocate functions
  let func_addrs : Array[Int] = []
  for code in mod.codes {
    let addr = store.alloc_func(code)
    func_addrs.push(addr)
  }

  // Allocate memories
  let mem_addrs : Array[Int] = []
  for mem_type in mod.memories {
    let mem = @runtime.Memory::new(mem_type.limits.min, mem_type.limits.max)
    let addr = store.alloc_mem(mem)
    mem_addrs.push(addr)
  }

  // For MVP, we don't handle imports, tables, globals yet
  let instance : @runtime.ModuleInstance = {
    types: mod.types,
    func_addrs,
    table_addrs: [],
    mem_addrs,
    global_addrs: [],
    exports: mod.exports,
    elem_segments: mod.elems,
    data_segments: mod.datas,
  }
  (store, instance)
}

///|
/// Find and call an exported function
pub fn call_exported_func(
  store : @runtime.Store,
  instance : @runtime.ModuleInstance,
  name : String,
  args : Array[@wasmoon.Value],
) -> Array[@wasmoon.Value] raise {
  // Find the export
  fn find_export(
    exports : Array[@wasmoon.Export],
    target : String,
  ) -> @wasmoon.Export? {
    loop 0 {
      idx =>
        if idx >= exports.length() {
          None
        } else {
          let exp = exports[idx]
          if exp.name == target {
            Some(exp)
          } else {
            continue idx + 1
          }
        }
    }
  }

  match find_export(instance.exports, name) {
    Some(exp) =>
      match exp.desc {
        Func(func_idx) => {
          let ctx = ExecContext::new(store)
          ctx.call_func(func_idx, args)
        }
        _ => raise @runtime.UndefinedElement
      }
    None => raise @runtime.UndefinedElement
  }
}

///|
test "execute simple add function" {
  // Create a simple module that adds two i32 values
  // Function signature: (i32, i32) -> i32
  // Function body: local.get 0, local.get 1, i32.add

  let add_func : @wasmoon.FunctionCode = {
    locals: [],
    body: [LocalGet(0), LocalGet(1), I32Add],
  }
  let func_type : @wasmoon.FuncType = {
    params: [@wasmoon.ValueType::I32, @wasmoon.ValueType::I32],
    results: [@wasmoon.ValueType::I32],
  }
  let mod : @wasmoon.Module = {
    types: [func_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "add", desc: @wasmoon.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [add_func],
    datas: [],
  }

  // Instantiate and call
  let (store, instance) = instantiate_module(mod)
  let args = [@wasmoon.Value::I32(5), @wasmoon.Value::I32(10)]
  let results = call_exported_func(store, instance, "add", args)
  match results[0] {
    I32(n) => inspect(n, content="15")
    _ => fail("Expected I32 result")
  }
}

///|
test "execute function with local variables" {
  // Function: (a, b) => { let tmp = a + b; return tmp * 2 }

  let func : @wasmoon.FunctionCode = {
    locals: [@wasmoon.ValueType::I32], // one local variable
    body: [
      LocalGet(0), // get a
      LocalGet(1), // get b
      I32Add, // a + b
      LocalSet(2), // store in local (index 2)
      LocalGet(2), // get local
      I32Const(2), // constant 2
      I32Mul, // tmp * 2
    ],
  }
  let func_type : @wasmoon.FuncType = {
    params: [@wasmoon.ValueType::I32, @wasmoon.ValueType::I32],
    results: [@wasmoon.ValueType::I32],
  }
  let mod : @wasmoon.Module = {
    types: [func_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "double_sum", desc: @wasmoon.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [func],
    datas: [],
  }
  let (store, instance) = instantiate_module(mod)
  let args = [@wasmoon.Value::I32(3), @wasmoon.Value::I32(4)]
  let results = call_exported_func(store, instance, "double_sum", args)
  match results[0] {
    I32(n) => inspect(n, content="14") // (3 + 4) * 2 = 14
    _ => fail("Expected I32 result")
  }
}

///|
test "execute i64 addition" {
  // Test i64 arithmetic: (a, b) => a + b
  let i64_add_func : @wasmoon.FunctionCode = {
    locals: [],
    body: [LocalGet(0), LocalGet(1), I64Add],
  }
  let func_type : @wasmoon.FuncType = {
    params: [@wasmoon.ValueType::I64, @wasmoon.ValueType::I64],
    results: [@wasmoon.ValueType::I64],
  }
  let mod : @wasmoon.Module = {
    types: [func_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "i64_add", desc: @wasmoon.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [i64_add_func],
    datas: [],
  }
  let (store, instance) = instantiate_module(mod)
  let args = [
    @wasmoon.Value::I64(1000000000000L),
    @wasmoon.Value::I64(2000000000000L),
  ]
  let results = call_exported_func(store, instance, "i64_add", args)
  match results[0] {
    I64(n) => inspect(n, content="3000000000000")
    _ => fail("Expected I64 result")
  }
}

///|
test "execute f32 arithmetic" {
  // Test f32 operations: (a, b) => a + b * 2.0
  let f32_func : @wasmoon.FunctionCode = {
    locals: [],
    body: [
      LocalGet(1), // b
      F32Const(2.0), // 2.0
      F32Mul, // b * 2.0
      LocalGet(0), // a
      F32Add,
    ],
  } // a + (b * 2.0)
  let func_type : @wasmoon.FuncType = {
    params: [@wasmoon.ValueType::F32, @wasmoon.ValueType::F32],
    results: [@wasmoon.ValueType::F32],
  }
  let mod : @wasmoon.Module = {
    types: [func_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "f32_test", desc: @wasmoon.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [f32_func],
    datas: [],
  }
  let (store, instance) = instantiate_module(mod)
  let args = [@wasmoon.Value::F32(3.5), @wasmoon.Value::F32(4.0)]
  let results = call_exported_func(store, instance, "f32_test", args)
  match results[0] {
    F32(f) => inspect(f, content="11.5") // 3.5 + 4.0 * 2.0 = 11.5
    _ => fail("Expected F32 result")
  }
}

///|
test "execute f64 arithmetic" {
  // Test f64 operations: (a, b) => (a - b) * 0.5
  let f64_func : @wasmoon.FunctionCode = {
    locals: [],
    body: [
      LocalGet(0), // a
      LocalGet(1), // b
      F64Sub, // a - b
      F64Const(0.5), // 0.5
      F64Mul,
    ],
  } // (a - b) * 0.5
  let func_type : @wasmoon.FuncType = {
    params: [@wasmoon.ValueType::F64, @wasmoon.ValueType::F64],
    results: [@wasmoon.ValueType::F64],
  }
  let mod : @wasmoon.Module = {
    types: [func_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "f64_test", desc: @wasmoon.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [f64_func],
    datas: [],
  }
  let (store, instance) = instantiate_module(mod)
  let args = [@wasmoon.Value::F64(10.0), @wasmoon.Value::F64(6.0)]
  let results = call_exported_func(store, instance, "f64_test", args)
  match results[0] {
    F64(d) => inspect(d, content="2") // (10.0 - 6.0) * 0.5 = 2.0
    _ => fail("Expected F64 result")
  }
}

///|
test "execute i64 comparison" {
  // Test i64 comparison: (a, b) => a < b
  let i64_cmp_func : @wasmoon.FunctionCode = {
    locals: [],
    body: [LocalGet(0), LocalGet(1), I64LtS],
  }
  let func_type : @wasmoon.FuncType = {
    params: [@wasmoon.ValueType::I64, @wasmoon.ValueType::I64],
    results: [@wasmoon.ValueType::I32],
  }
  let mod : @wasmoon.Module = {
    types: [func_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "i64_lt", desc: @wasmoon.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [i64_cmp_func],
    datas: [],
  }
  let (store, instance) = instantiate_module(mod)
  let args = [@wasmoon.Value::I64(100L), @wasmoon.Value::I64(200L)]
  let results = call_exported_func(store, instance, "i64_lt", args)
  match results[0] {
    I32(n) => inspect(n, content="1") // 100 < 200 = true (1)
    _ => fail("Expected I32 result")
  }
}

///|
test "numeric conversion: i32.wrap_i64" {
  let func : @wasmoon.FunctionCode = {
    locals: [],
    body: [LocalGet(0), I32WrapI64],
  }
  let func_type : @wasmoon.FuncType = {
    params: [@wasmoon.ValueType::I64],
    results: [@wasmoon.ValueType::I32],
  }
  let mod : @wasmoon.Module = {
    types: [func_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "wrap", desc: @wasmoon.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [func],
    datas: [],
  }
  let (store, instance) = instantiate_module(mod)
  // 0x0000000100000005 -> 0x00000005 = 5
  let args = [@wasmoon.Value::I64(4294967301L)]
  let results = call_exported_func(store, instance, "wrap", args)
  match results[0] {
    I32(n) => inspect(n, content="5")
    _ => fail("Expected I32 result")
  }
}

///|
test "numeric conversion: i64.extend_i32_s" {
  let func : @wasmoon.FunctionCode = {
    locals: [],
    body: [LocalGet(0), I64ExtendI32S],
  }
  let func_type : @wasmoon.FuncType = {
    params: [@wasmoon.ValueType::I32],
    results: [@wasmoon.ValueType::I64],
  }
  let mod : @wasmoon.Module = {
    types: [func_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "extend_s", desc: @wasmoon.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [func],
    datas: [],
  }
  let (store, instance) = instantiate_module(mod)
  // -1 (i32) -> -1 (i64)
  let args = [@wasmoon.Value::I32(-1)]
  let results = call_exported_func(store, instance, "extend_s", args)
  match results[0] {
    I64(n) => inspect(n, content="-1")
    _ => fail("Expected I64 result")
  }
}

///|
test "numeric conversion: f64.convert_i32_s" {
  let func : @wasmoon.FunctionCode = {
    locals: [],
    body: [LocalGet(0), F64ConvertI32S],
  }
  let func_type : @wasmoon.FuncType = {
    params: [@wasmoon.ValueType::I32],
    results: [@wasmoon.ValueType::F64],
  }
  let mod : @wasmoon.Module = {
    types: [func_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "convert", desc: @wasmoon.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [func],
    datas: [],
  }
  let (store, instance) = instantiate_module(mod)
  let args = [@wasmoon.Value::I32(-42)]
  let results = call_exported_func(store, instance, "convert", args)
  match results[0] {
    F64(d) => inspect(d, content="-42")
    _ => fail("Expected F64 result")
  }
}

///|
test "numeric conversion: i32.reinterpret_f32" {
  let func : @wasmoon.FunctionCode = {
    locals: [],
    body: [LocalGet(0), I32ReinterpretF32],
  }
  let func_type : @wasmoon.FuncType = {
    params: [@wasmoon.ValueType::F32],
    results: [@wasmoon.ValueType::I32],
  }
  let mod : @wasmoon.Module = {
    types: [func_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "reinterpret", desc: @wasmoon.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [func],
    datas: [],
  }
  let (store, instance) = instantiate_module(mod)
  // 1.0f32 的 IEEE 754 表示是 0x3F800000 = 1065353216
  let args = [@wasmoon.Value::F32(1.0)]
  let results = call_exported_func(store, instance, "reinterpret", args)
  match results[0] {
    I32(n) => inspect(n, content="1065353216")
    _ => fail("Expected I32 result")
  }
}

///|
test "saturating truncation: i32.trunc_sat_f32_s overflow" {
  let func : @wasmoon.FunctionCode = {
    locals: [],
    body: [LocalGet(0), I32TruncSatF32S],
  }
  let func_type : @wasmoon.FuncType = {
    params: [@wasmoon.ValueType::F32],
    results: [@wasmoon.ValueType::I32],
  }
  let mod : @wasmoon.Module = {
    types: [func_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "trunc_sat", desc: @wasmoon.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [func],
    datas: [],
  }
  let (store, instance) = instantiate_module(mod)
  // 超出 i32 最大值，应该饱和到 2147483647
  let args = [@wasmoon.Value::F32(3000000000.0)]
  let results = call_exported_func(store, instance, "trunc_sat", args)
  match results[0] {
    I32(n) => inspect(n, content="2147483647")
    _ => fail("Expected I32 result")
  }
}

///|
test "saturating truncation: i32.trunc_sat_f64_u negative" {
  let func : @wasmoon.FunctionCode = {
    locals: [],
    body: [LocalGet(0), I32TruncSatF64U],
  }
  let func_type : @wasmoon.FuncType = {
    params: [@wasmoon.ValueType::F64],
    results: [@wasmoon.ValueType::I32],
  }
  let mod : @wasmoon.Module = {
    types: [func_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "trunc_sat_u", desc: @wasmoon.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [func],
    datas: [],
  }
  let (store, instance) = instantiate_module(mod)
  // 负数对于无符号饱和截断应该返回 0
  let args = [@wasmoon.Value::F64(-100.0)]
  let results = call_exported_func(store, instance, "trunc_sat_u", args)
  match results[0] {
    I32(n) => inspect(n, content="0")
    _ => fail("Expected I32 result")
  }
}

///|
test "memory: i32.store and i32.load" {
  // Function: store value 42 at address 0, then load and return it
  let func : @wasmoon.FunctionCode = {
    locals: [],
    body: [
      I32Const(0), // address
      I32Const(42), // value
      I32Store(2, 0), // align=2, offset=0
      I32Const(0), // address
      I32Load(2, 0),
    ],
  } // align=2, offset=0
  let func_type : @wasmoon.FuncType = {
    params: [],
    results: [@wasmoon.ValueType::I32],
  }
  let mod : @wasmoon.Module = {
    types: [func_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [{ limits: { min: 1, max: None } }],
    globals: [],
    exports: [{ name: "test", desc: @wasmoon.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [func],
    datas: [],
  }
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "test", [])
  match results[0] {
    I32(n) => inspect(n, content="42")
    _ => fail("Expected I32 result")
  }
}

///|
test "memory: i64.store and i64.load" {
  let func : @wasmoon.FunctionCode = {
    locals: [],
    body: [
      I32Const(0), // address
      I64Const(1234567890123L), // value
      I64Store(3, 0), // align=3, offset=0
      I32Const(0), // address
      I64Load(3, 0),
    ],
  } // load
  let func_type : @wasmoon.FuncType = {
    params: [],
    results: [@wasmoon.ValueType::I64],
  }
  let mod : @wasmoon.Module = {
    types: [func_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [{ limits: { min: 1, max: None } }],
    globals: [],
    exports: [{ name: "test", desc: @wasmoon.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [func],
    datas: [],
  }
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "test", [])
  match results[0] {
    I64(n) => inspect(n, content="1234567890123")
    _ => fail("Expected I64 result")
  }
}

///|
test "memory: f32.store and f32.load" {
  let func : @wasmoon.FunctionCode = {
    locals: [],
    body: [
      I32Const(0), // address
      F32Const(3.14), // value
      F32Store(2, 0), // store
      I32Const(0), // address
      F32Load(2, 0),
    ],
  } // load
  let func_type : @wasmoon.FuncType = {
    params: [],
    results: [@wasmoon.ValueType::F32],
  }
  let mod : @wasmoon.Module = {
    types: [func_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [{ limits: { min: 1, max: None } }],
    globals: [],
    exports: [{ name: "test", desc: @wasmoon.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [func],
    datas: [],
  }
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "test", [])
  match results[0] {
    F32(f) => {
      // f32 has limited precision, check approximately
      let diff = (f - 3.14).abs()
      inspect(diff < 0.001, content="true")
    }
    _ => fail("Expected F32 result")
  }
}

///|
test "memory: load with offset" {
  // Store 100 at address 8, then load from address 0 with offset 8
  let func : @wasmoon.FunctionCode = {
    locals: [],
    body: [
      I32Const(8), // address
      I32Const(100), // value
      I32Store(2, 0), // store at address 8
      I32Const(0), // base address
      I32Load(2, 8),
    ],
  } // load from 0 + offset 8 = 8
  let func_type : @wasmoon.FuncType = {
    params: [],
    results: [@wasmoon.ValueType::I32],
  }
  let mod : @wasmoon.Module = {
    types: [func_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [{ limits: { min: 1, max: None } }],
    globals: [],
    exports: [{ name: "test", desc: @wasmoon.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [func],
    datas: [],
  }
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "test", [])
  match results[0] {
    I32(n) => inspect(n, content="100")
    _ => fail("Expected I32 result")
  }
}

///|
test "memory: i32.load8_s sign extension" {
  // Store 0xFF at address 0 (as i32), then load as signed byte
  // 0xFF as signed byte is -1
  let func : @wasmoon.FunctionCode = {
    locals: [],
    body: [
      I32Const(0), // address
      I32Const(255), // value (0xFF)
      I32Store8(0, 0), // store as byte
      I32Const(0), // address
      I32Load8S(0, 0),
    ],
  } // load as signed byte
  let func_type : @wasmoon.FuncType = {
    params: [],
    results: [@wasmoon.ValueType::I32],
  }
  let mod : @wasmoon.Module = {
    types: [func_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [{ limits: { min: 1, max: None } }],
    globals: [],
    exports: [{ name: "test", desc: @wasmoon.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [func],
    datas: [],
  }
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "test", [])
  match results[0] {
    I32(n) => inspect(n, content="-1")
    _ => fail("Expected I32 result")
  }
}

///|
test "memory: i32.load8_u zero extension" {
  // Store 0xFF at address 0, then load as unsigned byte
  // 0xFF as unsigned byte is 255
  let func : @wasmoon.FunctionCode = {
    locals: [],
    body: [
      I32Const(0), // address
      I32Const(255), // value (0xFF)
      I32Store8(0, 0), // store as byte
      I32Const(0), // address
      I32Load8U(0, 0),
    ],
  } // load as unsigned byte
  let func_type : @wasmoon.FuncType = {
    params: [],
    results: [@wasmoon.ValueType::I32],
  }
  let mod : @wasmoon.Module = {
    types: [func_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [{ limits: { min: 1, max: None } }],
    globals: [],
    exports: [{ name: "test", desc: @wasmoon.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [func],
    datas: [],
  }
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "test", [])
  match results[0] {
    I32(n) => inspect(n, content="255")
    _ => fail("Expected I32 result")
  }
}

///|
test "memory: memory.size and memory.grow" {
  // Check initial size (1 page), grow by 2 pages, return new size
  let func : @wasmoon.FunctionCode = {
    locals: [],
    body: [
      MemorySize, // get current size (1)
      Drop, // discard
      I32Const(2), // delta
      MemoryGrow, // grow by 2, returns old size (1)
      Drop, // discard old size
      MemorySize,
    ],
  } // get new size (3)
  let func_type : @wasmoon.FuncType = {
    params: [],
    results: [@wasmoon.ValueType::I32],
  }
  let mod : @wasmoon.Module = {
    types: [func_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [{ limits: { min: 1, max: None } }],
    globals: [],
    exports: [{ name: "test", desc: @wasmoon.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [func],
    datas: [],
  }
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "test", [])
  match results[0] {
    I32(n) => inspect(n, content="3")
    _ => fail("Expected I32 result")
  }
}

///|
test "control flow: simple block" {
  // block returns value from inner expression
  // (block (result i32) (i32.const 42))
  let func : @wasmoon.FunctionCode = {
    locals: [],
    body: [Block(Value(@wasmoon.ValueType::I32), [I32Const(42)])],
  }
  let func_type : @wasmoon.FuncType = {
    params: [],
    results: [@wasmoon.ValueType::I32],
  }
  let mod : @wasmoon.Module = {
    types: [func_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "test", desc: @wasmoon.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [func],
    datas: [],
  }
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "test", [])
  match results[0] {
    I32(n) => inspect(n, content="42")
    _ => fail("Expected I32 result")
  }
}

///|
test "control flow: br exits block" {
  // (block (result i32)
  //   (i32.const 10)
  //   (br 0)
  //   (i32.const 20)  ;; unreachable
  // )
  let func : @wasmoon.FunctionCode = {
    locals: [],
    body: [
      Block(Value(@wasmoon.ValueType::I32), [I32Const(10), Br(0), I32Const(20)]),
    ],
  }
  let func_type : @wasmoon.FuncType = {
    params: [],
    results: [@wasmoon.ValueType::I32],
  }
  let mod : @wasmoon.Module = {
    types: [func_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "test", desc: @wasmoon.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [func],
    datas: [],
  }
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "test", [])
  match results[0] {
    I32(n) => inspect(n, content="10")
    _ => fail("Expected I32 result")
  }
}

///|
test "control flow: br_if conditional" {
  // (func (param i32) (result i32)
  //   (block (result i32)
  //     (i32.const 100)
  //     (local.get 0)
  //     (br_if 0)  ;; if param != 0, exit with 100
  //     (drop)
  //     (i32.const 200)
  //   ))
  let func : @wasmoon.FunctionCode = {
    locals: [],
    body: [
      Block(Value(@wasmoon.ValueType::I32), [
        I32Const(100),
        LocalGet(0),
        BrIf(0),
        Drop,
        I32Const(200),
      ]),
    ],
  }
  let func_type : @wasmoon.FuncType = {
    params: [@wasmoon.ValueType::I32],
    results: [@wasmoon.ValueType::I32],
  }
  let mod : @wasmoon.Module = {
    types: [func_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "test", desc: @wasmoon.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [func],
    datas: [],
  }
  let (store, instance) = instantiate_module(mod)
  // Test with condition true (1) - should return 100
  let results1 = call_exported_func(store, instance, "test", [I32(1)])
  match results1[0] {
    I32(n) => inspect(n, content="100")
    _ => fail("Expected I32 result")
  }
  // Test with condition false (0) - should return 200
  let results2 = call_exported_func(store, instance, "test", [I32(0)])
  match results2[0] {
    I32(n) => inspect(n, content="200")
    _ => fail("Expected I32 result")
  }
}

///|
test "control flow: loop with br" {
  // Sum 1 to 5 using loop
  // (func (result i32)
  //   (local i32 i32)  ;; counter, sum
  //   (local.set 0 (i32.const 1))  ;; counter = 1
  //   (local.set 1 (i32.const 0))  ;; sum = 0
  //   (loop
  //     (local.set 1 (i32.add (local.get 1) (local.get 0)))  ;; sum += counter
  //     (local.set 0 (i32.add (local.get 0) (i32.const 1)))  ;; counter++
  //     (br_if 0 (i32.le_s (local.get 0) (i32.const 5)))     ;; if counter <= 5, loop
  //   )
  //   (local.get 1))  ;; return sum
  let func : @wasmoon.FunctionCode = {
    locals: [@wasmoon.ValueType::I32, @wasmoon.ValueType::I32], // counter, sum
    body: [
      I32Const(1),
      LocalSet(0), // counter = 1
      I32Const(0),
      LocalSet(1), // sum = 0
      Loop(Empty, [
        LocalGet(1),
        LocalGet(0),
        I32Add,
        LocalSet(1), // sum += counter
        LocalGet(0),
        I32Const(1),
        I32Add,
        LocalSet(0), // counter++
        LocalGet(0),
        I32Const(5),
        I32LeS,
        BrIf(0),
      ]), // if counter <= 5, continue
      LocalGet(1),
    ],
  } // return sum
  let func_type : @wasmoon.FuncType = {
    params: [],
    results: [@wasmoon.ValueType::I32],
  }
  let mod : @wasmoon.Module = {
    types: [func_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "test", desc: @wasmoon.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [func],
    datas: [],
  }
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "test", [])
  match results[0] {
    I32(n) => inspect(n, content="15") // 1+2+3+4+5 = 15
    _ => fail("Expected I32 result")
  }
}

///|
test "control flow: if-else" {
  // (func (param i32) (result i32)
  //   (if (result i32) (local.get 0)
  //     (then (i32.const 111))
  //     (else (i32.const 222))))
  let func : @wasmoon.FunctionCode = {
    locals: [],
    body: [
      LocalGet(0),
      If(Value(@wasmoon.ValueType::I32), [I32Const(111)], [I32Const(222)]),
    ],
  }
  let func_type : @wasmoon.FuncType = {
    params: [@wasmoon.ValueType::I32],
    results: [@wasmoon.ValueType::I32],
  }
  let mod : @wasmoon.Module = {
    types: [func_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "test", desc: @wasmoon.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [func],
    datas: [],
  }
  let (store, instance) = instantiate_module(mod)
  // Test with true (1)
  let results1 = call_exported_func(store, instance, "test", [I32(1)])
  match results1[0] {
    I32(n) => inspect(n, content="111")
    _ => fail("Expected I32 result")
  }
  // Test with false (0)
  let results2 = call_exported_func(store, instance, "test", [I32(0)])
  match results2[0] {
    I32(n) => inspect(n, content="222")
    _ => fail("Expected I32 result")
  }
}

///|
test "control flow: nested blocks with br" {
  // (block $outer (result i32)
  //   (block $inner
  //     (i32.const 50)
  //     (br 1)  ;; jump to outer
  //   )
  //   (i32.const 99))
  let func : @wasmoon.FunctionCode = {
    locals: [],
    body: [
      Block(Value(@wasmoon.ValueType::I32), [
        Block(Empty, [I32Const(50), Br(1)]),
        I32Const(99),
      ]),
    ],
  }
  let func_type : @wasmoon.FuncType = {
    params: [],
    results: [@wasmoon.ValueType::I32],
  }
  let mod : @wasmoon.Module = {
    types: [func_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "test", desc: @wasmoon.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [func],
    datas: [],
  }
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "test", [])
  match results[0] {
    I32(n) => inspect(n, content="50")
    _ => fail("Expected I32 result")
  }
}

///|
test "control flow: select" {
  // (func (param i32 i32 i32) (result i32)
  //   (select (local.get 0) (local.get 1) (local.get 2)))
  let func : @wasmoon.FunctionCode = {
    locals: [],
    body: [LocalGet(0), LocalGet(1), LocalGet(2), Select],
  }
  let func_type : @wasmoon.FuncType = {
    params: [
      @wasmoon.ValueType::I32,
      @wasmoon.ValueType::I32,
      @wasmoon.ValueType::I32,
    ],
    results: [@wasmoon.ValueType::I32],
  }
  let mod : @wasmoon.Module = {
    types: [func_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "test", desc: @wasmoon.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [func],
    datas: [],
  }
  let (store, instance) = instantiate_module(mod)
  // select(10, 20, 1) -> 10 (condition true)
  let results1 = call_exported_func(store, instance, "test", [
    I32(10),
    I32(20),
    I32(1),
  ])
  match results1[0] {
    I32(n) => inspect(n, content="10")
    _ => fail("Expected I32 result")
  }
  // select(10, 20, 0) -> 20 (condition false)
  let results2 = call_exported_func(store, instance, "test", [
    I32(10),
    I32(20),
    I32(0),
  ])
  match results2[0] {
    I32(n) => inspect(n, content="20")
    _ => fail("Expected I32 result")
  }
}
