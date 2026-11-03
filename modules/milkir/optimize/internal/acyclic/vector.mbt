// Splat rewrites must preserve the explicit lane width. Scalar arithmetic may
// have a wider intermediate, but a final integer splat truncates each lane.

///|
fn OptimizerSession::splat_source(
  self : OptimizerSession,
  value : @milkir.Value,
) -> (@milkir.VectorLane, @milkir.Value)? {
  guard self.definition(value) is Some(inst) &&
    inst.opcode is Vector(Splat(lane)) &&
    inst.operands is [source] else {
    return None
  }
  Some((lane, source))
}

///|
fn vector_integer_lane(lane : @milkir.VectorIntLane) -> @milkir.VectorLane {
  match lane {
    I8 => I8
    I16 => I16
    I32 => I32
    I64 => I64
  }
}

///|
/// Extract only full-width scalar integers. Const lanes are in Wasm byte
/// order. Narrow lanes need explicit truncation and sign extension instead.
fn OptimizerSession::project_integer_lane(
  self : OptimizerSession,
  vector : @milkir.Value,
  lane : @milkir.VectorLane,
  index : Int32,
  type_ : @milkir.Type,
) -> @milkir.Value? {
  guard self.definition(vector) is Some(definition) else { return None }
  match definition.opcode {
    Vector(Splat(source_lane)) if lane == source_lane =>
      definition.operands.get(0)
    Vector(Const(bytes)) if bytes.length() == 16 => {
      let width = if type_ == I32 { 4 } else { 8 }
      let start = index * width
      let mut bits = 0UL
      for offset in 0..<width {
        bits = bits |
          (bytes[start + offset].to_int().to_uint64() << (offset * 8))
      }
      let scalar = if type_ == I32 {
        bits.to_uint().reinterpret_as_int().to_int64()
      } else {
        bits.reinterpret_as_int64()
      }
      self.stage_pure_candidate(Scalar(IntConst(scalar)), [], type_)
    }
    _ => None
  }
}

///|
fn OptimizerSession::rewrite_integer_lane_projection(
  self : OptimizerSession,
  inst : @milkir.Inst,
  lane : @milkir.VectorLane,
  index : Int32,
  prefix : Array[@milkir.Inst],
) -> Bool {
  guard inst.operands is [vector] &&
    inst.first_result() is Some(result) &&
    self.definition(vector) is Some(definition) else {
    return false
  }
  let marker = self.begin_candidates()
  if self.project_integer_lane(vector, lane, index, result.ty) is Some(value) {
    self.commit_candidates(marker, prefix)
    return self.replace_with_alias(inst, value)
  }
  guard self.has_single_use(vector) && definition.operands is [left, right] else {
    return false
  }
  let scalar : @milkir.IntBinaryOp = match definition.opcode {
    Vector(IntBinary(Add, width)) if vector_integer_lane(width) == lane => Add
    Vector(IntBinary(Sub, width)) if vector_integer_lane(width) == lane => Sub
    Vector(IntBinary(Mul, width)) if vector_integer_lane(width) == lane => Mul
    Vector(Bitwise(And)) => And
    Vector(Bitwise(Or)) => Or
    Vector(Bitwise(Xor)) => Xor
    _ => return false
  }
  if self.project_integer_lane(left, lane, index, result.ty) is Some(a) &&
    self.project_integer_lane(right, lane, index, result.ty) is Some(b) &&
    self.stage_pure_candidate(Scalar(IntBinary(scalar)), [a, b], result.ty)
    is Some(value) &&
    self.commit_candidates_if_cheaper(
      marker,
      1 + pure_candidate_cost(definition.opcode),
      prefix,
    ) {
    return self.replace_with_alias(inst, value)
  }
  self.discard_candidates(marker)
  false
}

///|
fn OptimizerSession::rewrite_vector(
  self : OptimizerSession,
  inst : @milkir.Inst,
  op : @milkir.VectorOp,
  prefix : Array[@milkir.Inst],
) -> Bool {
  match op {
    ExtractLane(I32, None, index) if index >= 0 && index < 4 =>
      self.rewrite_integer_lane_projection(inst, I32, index, prefix)
    ExtractLane(I64, None, index) if index >= 0 && index < 2 =>
      self.rewrite_integer_lane_projection(inst, I64, index, prefix)
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
      inst.set_opcode(Vector(Const(bytes)))
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
      let scalar : @milkir.IntBinaryOp = match op {
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
