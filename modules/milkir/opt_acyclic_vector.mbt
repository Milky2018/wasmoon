// Splat rewrites must preserve the explicit lane width. Scalar arithmetic may
// have a wider intermediate, but a final integer splat truncates each lane.

///|
fn OptimizerSession::splat_source(
  self : OptimizerSession,
  value : Value,
) -> (VectorLane, Value)? {
  guard self.definition(value) is Some(inst) &&
    inst.opcode is Vector(Splat(lane)) &&
    inst.operands is [source] else {
    return None
  }
  Some((lane, source))
}

///|
fn vector_integer_lane(lane : VectorIntLane) -> VectorLane {
  match lane {
    I8 => I8
    I16 => I16
    I32 => I32
    I64 => I64
  }
}

///|
fn OptimizerSession::rewrite_vector(
  self : OptimizerSession,
  inst : Inst,
  op : VectorOp,
  prefix : Array[Inst],
) -> Bool {
  match op {
    Splat(lane) => {
      guard inst.operands is [source] else { return false }
      let bits = match lane {
        I8 | I16 | I32 | I64 =>
          self.int_constant(source).map(value => value.reinterpret_as_uint64())
        F32 | F64 => self.float_bits(source)
      }
      guard bits is Some(bits) else { return false }
      let bytes_per_lane = match lane {
        I8 => 1
        I16 => 2
        I32 | F32 => 4
        I64 | F64 => 8
      }
      let bytes = Bytes::makei(16, i => {
        ((bits >> (i % bytes_per_lane * 8)) & 255UL).to_byte()
      })
      inst.opcode = Vector(Const(bytes))
      inst.operands.clear()
      true
    }
    Bitwise(And | Or | Xor) | IntBinary(Add | Sub | Mul, _) => {
      guard inst.operands is [left, right] &&
        self.splat_source(left) is Some((lane, a)) &&
        self.splat_source(right) is Some((right_lane, b)) &&
        lane == right_lane &&
        lane is (I8 | I16 | I32 | I64) &&
        self.has_single_use(left) &&
        self.has_single_use(right) else {
        return false
      }
      let scalar : IntBinaryOp = match op {
        Bitwise(And) => And
        Bitwise(Or) => Or
        Bitwise(Xor) => Xor
        IntBinary(Add, int_lane) if vector_integer_lane(int_lane) == lane => Add
        IntBinary(Sub, int_lane) if vector_integer_lane(int_lane) == lane => Sub
        IntBinary(Mul, int_lane) if vector_integer_lane(int_lane) == lane => Mul
        _ => return false
      }
      let marker = self.begin_candidates()
      if self.stage_pure_candidate(Scalar(IntBinary(scalar)), [a, b], a.ty)
        is Some(value) &&
        self.stage_pure_candidate(Vector(Splat(lane)), [value], V128)
        is Some(result) &&
        self.commit_candidates_if_cheaper(
          marker,
          2 + pure_candidate_cost(inst.opcode),
          prefix,
        ) {
        return self.replace_with_alias(inst, result)
      }
      self.discard_candidates(marker)
      false
    }
    _ => false
  }
}
