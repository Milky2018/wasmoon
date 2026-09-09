///|
fn ExecContext::canonicalize_nan_result(
  self : ExecContext,
  instr : @types.Instruction,
) -> Unit raise @runtime.RuntimeError {
  let width = match instr {
    F32Add
    | F32Sub
    | F32Mul
    | F32Div
    | F32Min
    | F32Max
    | F32Sqrt
    | F32Ceil
    | F32Floor
    | F32Trunc
    | F32Nearest
    | F32DemoteF64 => {
      let value = self.stack.pop_f32()
      self.stack.push(
        F32(
          if value.is_nan() {
            Float::reinterpret_from_int(0x7fc00000)
          } else {
            value
          },
        ),
      )
      return
    }
    F64Add
    | F64Sub
    | F64Mul
    | F64Div
    | F64Min
    | F64Max
    | F64Sqrt
    | F64Ceil
    | F64Floor
    | F64Trunc
    | F64Nearest
    | F64PromoteF32 => {
      let value = self.stack.pop_f64()
      self.stack.push(
        F64(
          if value.is_nan() {
            0x7ff8000000000000L.reinterpret_as_double()
          } else {
            value
          },
        ),
      )
      return
    }
    F32x4Add
    | F32x4Sub
    | F32x4Mul
    | F32x4Div
    | F32x4Min
    | F32x4Max
    | F32x4Sqrt
    | F32x4Ceil
    | F32x4Floor
    | F32x4Trunc
    | F32x4Nearest
    | F32x4DemoteF64x2Zero
    | F32x4RelaxedMadd
    | F32x4RelaxedNmadd => 4
    F64x2Add
    | F64x2Sub
    | F64x2Mul
    | F64x2Div
    | F64x2Min
    | F64x2Max
    | F64x2Sqrt
    | F64x2Ceil
    | F64x2Floor
    | F64x2Trunc
    | F64x2Nearest
    | F64x2PromoteLowF32x4
    | F64x2RelaxedMadd
    | F64x2RelaxedNmadd => 8
    _ => return
  }
  let value = self.stack.pop_v128()
  let bytes = value.to_array()
  let exponent = if width == 4 { 0x7f800000L } else { 0x7ff0000000000000L }
  let payload = if width == 4 { 0x007fffffL } else { 0x000fffffffffffffL }
  let canonical = if width == 4 { 0x7fc00000L } else { 0x7ff8000000000000L }
  for offset = 0; offset < 16; offset = offset + width {
    let mut bits = 0L
    for i in 0..<width {
      bits = bits | (bytes[offset + i].to_int().to_int64() << (8 * i))
    }
    if (bits & exponent) == exponent && (bits & payload) != 0L {
      for i in 0..<width {
        bytes[offset + i] = (canonical >> (8 * i)).to_byte()
      }
    }
  }
  self.stack.push(V128(Bytes::from_array(bytes)))
}
