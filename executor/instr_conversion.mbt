// Conversion Instructions - type conversion and reinterpret operations

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
      let unsigned = a.reinterpret_as_uint64()
      self.stack.push(F64(unsigned.to_double()))
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
    _ => raise @runtime.RuntimeError::Unreachable
  }
}
