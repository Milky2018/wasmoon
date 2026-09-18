///|
pub fn is_cheap_rematerializable_constant(inst : @milkir.Inst) -> Bool {
  guard inst.operands.is_empty() && inst.results is [result] else {
    return false
  }
  guard inst.opcode is Scalar(IntConst(raw)) else { return false }
  let (bits, lane_count) = match result.ty {
    I32 => (raw.reinterpret_as_uint64() & 0xFFFFFFFFUL, 2)
    I64 => (raw.reinterpret_as_uint64(), 4)
    _ => return false
  }
  let mut nonzero_lanes = 0
  for lane in 0..<lane_count {
    if ((bits >> (lane * 16)) & 0xFFFFUL) != 0UL {
      nonzero_lanes += 1
    }
  }
  nonzero_lanes <= 1
}
