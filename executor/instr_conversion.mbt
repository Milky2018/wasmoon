// Conversion Instructions - type conversion and reinterpret operations

// Constants for conversion bounds (using powers of 2 for precision)

///|
let pow2_32 : Double = 4294967296.0 // 2^32, exactly representable

///|
let pow2_31 : Double = 2147483648.0 // 2^31, exactly representable

///|
let pow2_63 : Double = 2.0.pow(63.0) // 2^63, exactly representable

///|
let pow2_64 : Double = 2.0.pow(64.0) // 2^64, exactly representable

///|
/// Execute conversion instruction
fn ExecContext::exec_conversion(
  self : ExecContext,
  instr : @types.Instruction,
) -> Unit raise {
  match instr {
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
      self.stack.push(I64(a.reinterpret_as_uint().to_int64()))
    }
    // i32.trunc_f32_s: f32 -> i32 (有符号截断)
    I32TruncF32S => {
      let a = self.stack.pop_f32()
      if a.is_nan() {
        raise @runtime.InvalidConversion
      }
      let d = a.to_double()
      if d >= pow2_31 || d < -pow2_31 {
        raise @runtime.IntegerOverflow
      }
      self.stack.push(I32(a.to_int()))
    }
    // i32.trunc_f32_u: f32 -> i32 (无符号截断)
    I32TruncF32U => {
      let a = self.stack.pop_f32()
      if a.is_nan() {
        raise @runtime.InvalidConversion
      }
      let d = a.to_double()
      // Values in (-1, 0) truncate to 0, only d <= -1 is overflow
      if d >= pow2_32 || d <= -1.0 {
        raise @runtime.IntegerOverflow
      }
      self.stack.push(I32(d.to_uint().reinterpret_as_int()))
    }
    // i32.trunc_f64_s: f64 -> i32 (有符号截断)
    I32TruncF64S => {
      let a = self.stack.pop_f64()
      if a.is_nan() {
        raise @runtime.InvalidConversion
      }
      // -2147483649.0 would truncate to -2147483649 (out of range)
      // -2147483648.9 would truncate to -2147483648 (in range)
      if a >= pow2_31 || a <= -(pow2_31 + 1.0) {
        raise @runtime.IntegerOverflow
      }
      self.stack.push(I32(a.to_int()))
    }
    // i32.trunc_f64_u: f64 -> i32 (无符号截断)
    I32TruncF64U => {
      let a = self.stack.pop_f64()
      if a.is_nan() {
        raise @runtime.InvalidConversion
      }
      if a >= pow2_32 || a <= -1.0 {
        raise @runtime.IntegerOverflow
      }
      self.stack.push(I32(a.to_uint().reinterpret_as_int()))
    }
    // i64.trunc_f32_s: f32 -> i64 (有符号截断)
    I64TruncF32S => {
      let a = self.stack.pop_f32()
      if a.is_nan() {
        raise @runtime.InvalidConversion
      }
      let d = a.to_double()
      if d >= pow2_63 || d < -pow2_63 {
        raise @runtime.IntegerOverflow
      }
      self.stack.push(I64(d.to_int64()))
    }
    // i64.trunc_f32_u: f32 -> i64 (无符号截断)
    I64TruncF32U => {
      let a = self.stack.pop_f32()
      if a.is_nan() {
        raise @runtime.InvalidConversion
      }
      let d = a.to_double()
      if d >= pow2_64 || d <= -1.0 {
        raise @runtime.IntegerOverflow
      }
      // For values >= 2^63, manually compute as: (d - 2^63) + MIN_I64
      let result = if d >= pow2_63 {
        let offset = (d - pow2_63).to_int64()
        offset + -9223372036854775808L
      } else {
        d.to_int64()
      }
      self.stack.push(I64(result))
    }
    // i64.trunc_f64_s: f64 -> i64 (有符号截断)
    I64TruncF64S => {
      let a = self.stack.pop_f64()
      if a.is_nan() {
        raise @runtime.InvalidConversion
      }
      if a >= pow2_63 || a < -pow2_63 {
        raise @runtime.IntegerOverflow
      }
      self.stack.push(I64(a.to_int64()))
    }
    // i64.trunc_f64_u: f64 -> i64 (无符号截断)
    I64TruncF64U => {
      let a = self.stack.pop_f64()
      if a.is_nan() {
        raise @runtime.InvalidConversion
      }
      if a >= pow2_64 || a <= -1.0 {
        raise @runtime.IntegerOverflow
      }
      // For values >= 2^63, manually compute as: (a - 2^63) + MIN_I64
      let result = if a >= pow2_63 {
        let offset = (a - pow2_63).to_int64()
        offset + -9223372036854775808L
      } else {
        a.to_int64()
      }
      self.stack.push(I64(result))
    }
    // f32.convert_i32_s: i32 -> f32 (有符号转换)
    F32ConvertI32S => {
      let a = self.stack.pop_i32()
      self.stack.push(F32(Float::from_int(a)))
    }
    // f32.convert_i32_u: i32 -> f32 (无符号转换)
    F32ConvertI32U => {
      let a = self.stack.pop_i32()
      self.stack.push(F32(Float::from_uint(a.reinterpret_as_uint())))
    }
    // f32.convert_i64_s: i64 -> f32 (有符号转换)
    F32ConvertI64S => {
      let a = self.stack.pop_i64()
      self.stack.push(F32(Float::from_int64(a)))
    }
    // f32.convert_i64_u: i64 -> f32 (无符号转换)
    F32ConvertI64U => {
      let a = self.stack.pop_i64()
      self.stack.push(F32(Float::from_uint64(a.reinterpret_as_uint64())))
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
      self.stack.push(F64(a.reinterpret_as_uint64().to_double()))
    }
    // f32.demote_f64: f64 -> f32
    F32DemoteF64 => {
      let a = self.stack.pop_f64()
      self.stack.push(F32(Float::from_double(a)))
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
      self.stack.push(F32(Float::reinterpret_from_int(a)))
    }
    // f64.reinterpret_i64: i64 的位模式 -> f64
    F64ReinterpretI64 => {
      let a = self.stack.pop_i64()
      self.stack.push(F64(a.reinterpret_as_double()))
    }
    _ => raise @runtime.RuntimeError::Unreachable
  }
}

///|
/// Execute saturating truncation instruction
fn ExecContext::exec_trunc_sat(
  self : ExecContext,
  instr : @types.Instruction,
) -> Unit raise {
  match instr {
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
      } else if d >= pow2_63 {
        9223372036854775807L
      } else if d <= -pow2_63 {
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
      } else if d >= pow2_64 {
        -1L // 0xFFFFFFFFFFFFFFFF as signed
      } else if d >= pow2_63 {
        let offset = (d - pow2_63).to_int64()
        offset + -9223372036854775808L
      } else {
        d.to_int64()
      }
      self.stack.push(I64(result))
    }
    // i64.trunc_sat_f64_s: f64 -> i64 (饱和有符号截断)
    I64TruncSatF64S => {
      let a = self.stack.pop_f64()
      let result = if a.is_nan() {
        0L
      } else if a >= pow2_63 {
        9223372036854775807L
      } else if a <= -pow2_63 {
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
      } else if a >= pow2_64 {
        -1L // 0xFFFFFFFFFFFFFFFF as signed
      } else if a >= pow2_63 {
        let offset = (a - pow2_63).to_int64()
        offset + -9223372036854775808L
      } else {
        a.to_int64()
      }
      self.stack.push(I64(result))
    }
    _ => raise @runtime.RuntimeError::Unreachable
  }
}
