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
) -> Unit raise @runtime.RuntimeError {
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

    // Control flow - simplified for MVP
    Nop => ()
    Return => () // Handled by caller
    _ => raise @runtime.RuntimeError::Unreachable // Unsupported instruction in MVP
  }
}

///|
/// Execute a sequence of instructions
fn ExecContext::exec_expr(
  self : ExecContext,
  instrs : Array[@wasmoon.Instruction],
) -> Unit raise @runtime.RuntimeError {
  for i = 0; i < instrs.length(); i = i + 1 {
    let instr = instrs[i]
    match instr {
      Return => break // Exit early on return
      _ => self.exec_instr(instr)
    }
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
) -> Array[@wasmoon.Value] raise @runtime.RuntimeError {
  let func = self.store.get_func(func_idx)

  // Create locals array: params + local variables
  let locals : Array[@wasmoon.Value] = []

  // Add parameters
  for i = 0; i < args.length(); i = i + 1 {
    locals.push(args[i])
  }

  // Add local variables (initialized to 0/null)
  for i = 0; i < func.locals.length(); i = i + 1 {
    let local_type = func.locals[i]
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
  for i = 0; i < mod.codes.length(); i = i + 1 {
    let addr = store.alloc_func(mod.codes[i])
    func_addrs.push(addr)
  }

  // For MVP, we don't handle imports, tables, memories, globals yet
  let instance : @runtime.ModuleInstance = {
    types: mod.types,
    func_addrs,
    table_addrs: [],
    mem_addrs: [],
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
) -> Array[@wasmoon.Value] raise @runtime.RuntimeError {
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
