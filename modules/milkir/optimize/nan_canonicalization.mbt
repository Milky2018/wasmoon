///|
priv enum NanResult {
  Scalar
  Vector(@milkir.VectorFloatLane)
}

///|
fn arithmetic_nan_result(opcode : @milkir.Opcode) -> NanResult? {
  match opcode {
    Scalar(FloatBinary(_))
    | Scalar(FloatUnary(Sqrt | Ceil | Floor | Trunc | Nearest))
    | Scalar(Convert(FloatPromote | FloatDemote)) => Some(Scalar)
    Vector(FloatBinary(Add | Sub | Mul | Div | Min | Max, lane))
    | Vector(FloatUnary(Sqrt | Ceil | Floor | Trunc | Nearest, lane))
    | Vector(Relaxed(Fma(lane, _))) => Some(Vector(lane))
    Vector(Convert(DemoteF64ToF32Zero)) => Some(Vector(F32))
    Vector(Convert(PromoteLowF32ToF64)) => Some(Vector(F64))
    _ => None
  }
}

///|
/// Replace arithmetic NaNs before their bits can be observed by consumers.
/// Constants, loads, sign operations, and pseudo-min/max retain their bits.
/// Run once before optimization on the source-level floating operations.
pub fn canonicalize_nans(func : @milkir.Function) -> Unit {
  for block in func.blocks {
    let rewritten : Array[@milkir.Inst] = []
    for id in block.instruction_ids() {
      let inst = func.instruction_by_id(id).unwrap()
      guard arithmetic_nan_result(inst.opcode) is Some(shape) else {
        rewritten.push(inst)
        continue
      }
      let result = inst.first_result().unwrap()
      let raw = func.new_value(result.ty)
      let arithmetic = func.new_inst(inst.opcode, inst.args.copy(), [raw])
      for metadata in inst.metadata {
        arithmetic.add_metadata(metadata)
      }
      rewritten.push(arithmetic)
      let canonical = func.new_value(result.ty)
      match shape {
        Scalar => {
          let constant : @milkir.Opcode = match result.ty {
            F32 => Scalar(FloatConst32(0x7fc00000U))
            _ => Scalar(FloatConst64(0x7ff8000000000000UL))
          }
          rewritten.push(func.new_inst(constant, [], [canonical]))
          let is_nan = func.new_value(I32)
          rewritten.push(
            func.new_inst(Scalar(FloatCompare(Ne)), [raw, raw], [is_nan]),
          )
          inst.set_opcode(Scalar(Select))
          inst.args.clear()
          for value in [is_nan, canonical, raw] {
            inst.args.push(value)
          }
          rewritten.push(inst)
        }
        Vector(lane) => {
          let bits = match lane {
            F32 => 0x7fc00000L
            F64 => 0x7ff8000000000000L
          }
          let width = match lane {
            F32 => 4
            F64 => 8
          }
          let bytes : Array[Byte] = Array::make(16, 0)
          for i in 0..<16 {
            bytes[i] = (bits >> (i % width * 8)).to_byte()
          }
          rewritten.push(
            func.new_inst(Vector(Const(Bytes::from_array(bytes))), [], [
              canonical,
            ]),
          )
          let is_nan = func.new_value(V128)
          rewritten.push(
            func.new_inst(Vector(FloatCompare(Ne, lane)), [raw, raw], [is_nan]),
          )
          inst.set_opcode(Vector(Bitwise(Bitselect)))
          inst.args.clear()
          for value in [canonical, raw, is_nan] {
            inst.args.push(value)
          }
          rewritten.push(inst)
        }
      }
    }
    block.set_instructions(rewritten)
  }
}
