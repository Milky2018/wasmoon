// Convenience constructors: one named function per opcode, each a thin
// wrapper over `EGraph::add`.
//
// Bulk without depth. Kept apart so that adding an opcode does not grow
// the file holding the congruence machinery.

// ============================================================================
// Helper constructors for common e-nodes
// ============================================================================

///|
pub fn EGraph::add_const(self : EGraph, value : Int64) -> EClassId {
  self.add({ op: Const(value), children: [], })
}

///|
pub fn EGraph::add_var(self : EGraph, var_id : Int) -> EClassId {
  self.add({ op: Var(var_id), children: [], })
}

///|
pub fn EGraph::add_binop(
  self : EGraph,
  op : EOpcode,
  lhs : EClassId,
  rhs : EClassId,
) -> EClassId {
  self.add({ op, children: [lhs, rhs], })
}

///|
pub fn EGraph::add_add(
  self : EGraph,
  lhs : EClassId,
  rhs : EClassId,
) -> EClassId {
  self.add_binop(Add, lhs, rhs)
}

///|
pub fn EGraph::add_sub(
  self : EGraph,
  lhs : EClassId,
  rhs : EClassId,
) -> EClassId {
  self.add_binop(Sub, lhs, rhs)
}

///|
pub fn EGraph::add_mul(
  self : EGraph,
  lhs : EClassId,
  rhs : EClassId,
) -> EClassId {
  self.add_binop(Mul, lhs, rhs)
}

///|
pub fn EGraph::add_shl(
  self : EGraph,
  lhs : EClassId,
  rhs : EClassId,
) -> EClassId {
  self.add_binop(Shl, lhs, rhs)
}

///|
pub fn EGraph::add_and(
  self : EGraph,
  lhs : EClassId,
  rhs : EClassId,
) -> EClassId {
  self.add_binop(And, lhs, rhs)
}

///|
pub fn EGraph::add_or(
  self : EGraph,
  lhs : EClassId,
  rhs : EClassId,
) -> EClassId {
  self.add_binop(Or, lhs, rhs)
}

///|
pub fn EGraph::add_xor(
  self : EGraph,
  lhs : EClassId,
  rhs : EClassId,
) -> EClassId {
  self.add_binop(Xor, lhs, rhs)
}

///|
/// Add a negation node: -x
pub fn EGraph::add_neg(self : EGraph, operand : EClassId) -> EClassId {
  self.add({ op: Neg, children: [operand], })
}

///|
/// Add a bitwise NOT node: ~x
pub fn EGraph::add_bnot(self : EGraph, operand : EClassId) -> EClassId {
  self.add({ op: Bnot, children: [operand], })
}

///|
pub fn EGraph::add_sdiv(
  self : EGraph,
  lhs : EClassId,
  rhs : EClassId,
) -> EClassId {
  self.add_binop(Sdiv, lhs, rhs)
}

///|
pub fn EGraph::add_udiv(
  self : EGraph,
  lhs : EClassId,
  rhs : EClassId,
) -> EClassId {
  self.add_binop(Udiv, lhs, rhs)
}

///|
pub fn EGraph::add_srem(
  self : EGraph,
  lhs : EClassId,
  rhs : EClassId,
) -> EClassId {
  self.add_binop(Srem, lhs, rhs)
}

///|
pub fn EGraph::add_urem(
  self : EGraph,
  lhs : EClassId,
  rhs : EClassId,
) -> EClassId {
  self.add_binop(Urem, lhs, rhs)
}

///|
pub fn EGraph::add_ushr(
  self : EGraph,
  lhs : EClassId,
  rhs : EClassId,
) -> EClassId {
  self.add_binop(Ushr, lhs, rhs)
}

///|
pub fn EGraph::add_sshr(
  self : EGraph,
  lhs : EClassId,
  rhs : EClassId,
) -> EClassId {
  self.add_binop(Sshr, lhs, rhs)
}

///|
pub fn EGraph::add_rotl(
  self : EGraph,
  lhs : EClassId,
  rhs : EClassId,
) -> EClassId {
  self.add_binop(Rotl, lhs, rhs)
}

///|
pub fn EGraph::add_rotr(
  self : EGraph,
  lhs : EClassId,
  rhs : EClassId,
) -> EClassId {
  self.add_binop(Rotr, lhs, rhs)
}

///|
/// Add a count leading zeros node
pub fn EGraph::add_clz(self : EGraph, operand : EClassId) -> EClassId {
  self.add({ op: Clz, children: [operand], })
}

///|
/// Add a count trailing zeros node
pub fn EGraph::add_ctz(self : EGraph, operand : EClassId) -> EClassId {
  self.add({ op: Ctz, children: [operand], })
}

///|
/// Add a population count node
pub fn EGraph::add_popcnt(self : EGraph, operand : EClassId) -> EClassId {
  self.add({ op: Popcnt, children: [operand], })
}

///|
/// Add a byte swap node
pub fn EGraph::add_bswap(self : EGraph, operand : EClassId) -> EClassId {
  self.add({ op: Bswap, children: [operand], })
}

///|
/// Add a bit reverse node
pub fn EGraph::add_bitrev(self : EGraph, operand : EClassId) -> EClassId {
  self.add({ op: Bitrev, children: [operand], })
}

///|
/// Add an integer compare node with condition code
pub fn EGraph::add_icmp(
  self : EGraph,
  cc : Int,
  lhs : EClassId,
  rhs : EClassId,
) -> EClassId {
  self.add({ op: Icmp(cc), children: [lhs, rhs], })
}

///|
/// Add an equality comparison node
pub fn EGraph::add_eq(
  self : EGraph,
  lhs : EClassId,
  rhs : EClassId,
) -> EClassId {
  self.add_binop(Eq, lhs, rhs)
}

///|
/// Add a not-equal comparison node
pub fn EGraph::add_ne(
  self : EGraph,
  lhs : EClassId,
  rhs : EClassId,
) -> EClassId {
  self.add_binop(Ne, lhs, rhs)
}

///|
/// Add a select node: select(cond, a, b) = cond ? a : b
pub fn EGraph::add_select(
  self : EGraph,
  cond : EClassId,
  a : EClassId,
  b : EClassId,
) -> EClassId {
  self.add({ op: Select, children: [cond, a, b], })
}

///|
/// Add a boolean mask node: 0 -> 0, nonzero -> -1
pub fn EGraph::add_bmask(self : EGraph, operand : EClassId) -> EClassId {
  self.add({ op: Bmask, children: [operand], })
}

///|
/// Add an integer reduce (truncate) node with type info
pub fn EGraph::add_ireduce(
  self : EGraph,
  operand : EClassId,
  from_bits? : Int = 64,
  to_bits? : Int = 32,
) -> EClassId {
  self.add({ op: Ireduce(from_bits, to_bits), children: [operand], })
}

///|
/// Add an unsigned extend node with type info
pub fn EGraph::add_uextend(
  self : EGraph,
  operand : EClassId,
  from_bits? : Int = 32,
  to_bits? : Int = 64,
) -> EClassId {
  self.add({ op: Uextend(from_bits, to_bits), children: [operand], })
}

///|
/// Add a signed extend node with type info
pub fn EGraph::add_sextend(
  self : EGraph,
  operand : EClassId,
  from_bits? : Int = 32,
  to_bits? : Int = 64,
) -> EClassId {
  self.add({ op: Sextend(from_bits, to_bits), children: [operand], })
}

// ============================================================================
// Floating point helper constructors
// ============================================================================

///|
/// Add a float constant node (bits stored as UInt64)
pub fn EGraph::add_fconst(self : EGraph, bits : UInt64) -> EClassId {
  self.add({ op: Fconst(bits), children: [], })
}

///|
/// Add a float add node
pub fn EGraph::add_fadd(
  self : EGraph,
  left : EClassId,
  right : EClassId,
) -> EClassId {
  self.add({ op: Fadd, children: [left, right], })
}

///|
/// Add a float subtract node
pub fn EGraph::add_fsub(
  self : EGraph,
  left : EClassId,
  right : EClassId,
) -> EClassId {
  self.add({ op: Fsub, children: [left, right], })
}

///|
/// Add a float multiply node
pub fn EGraph::add_fmul(
  self : EGraph,
  left : EClassId,
  right : EClassId,
) -> EClassId {
  self.add({ op: Fmul, children: [left, right], })
}

///|
/// Add a float divide node
pub fn EGraph::add_fdiv(
  self : EGraph,
  left : EClassId,
  right : EClassId,
) -> EClassId {
  self.add({ op: Fdiv, children: [left, right], })
}

///|
/// Add a float min node
pub fn EGraph::add_fmin(
  self : EGraph,
  left : EClassId,
  right : EClassId,
) -> EClassId {
  self.add({ op: Fmin, children: [left, right], })
}

///|
/// Add a float max node
pub fn EGraph::add_fmax(
  self : EGraph,
  left : EClassId,
  right : EClassId,
) -> EClassId {
  self.add({ op: Fmax, children: [left, right], })
}

///|
/// Add a float copysign node
pub fn EGraph::add_fcopysign(
  self : EGraph,
  mag : EClassId,
  sign : EClassId,
) -> EClassId {
  self.add({ op: Fcopysign, children: [mag, sign], })
}

///|
/// Add a float negate node
pub fn EGraph::add_fneg(self : EGraph, operand : EClassId) -> EClassId {
  self.add({ op: Fneg, children: [operand], })
}

///|
/// Add a float absolute value node
pub fn EGraph::add_fabs(self : EGraph, operand : EClassId) -> EClassId {
  self.add({ op: Fabs, children: [operand], })
}

///|
/// Add a float square root node
pub fn EGraph::add_fsqrt(self : EGraph, operand : EClassId) -> EClassId {
  self.add({ op: Fsqrt, children: [operand], })
}

///|
/// Add a float ceiling node
pub fn EGraph::add_fceil(self : EGraph, operand : EClassId) -> EClassId {
  self.add({ op: Fceil, children: [operand], })
}

///|
/// Add a float floor node
pub fn EGraph::add_ffloor(self : EGraph, operand : EClassId) -> EClassId {
  self.add({ op: Ffloor, children: [operand], })
}

///|
/// Add a float truncate node
pub fn EGraph::add_ftrunc(self : EGraph, operand : EClassId) -> EClassId {
  self.add({ op: Ftrunc, children: [operand], })
}

///|
/// Add a float round to nearest node
pub fn EGraph::add_fnearest(self : EGraph, operand : EClassId) -> EClassId {
  self.add({ op: Fnearest, children: [operand], })
}

///|
/// Add a float compare node
pub fn EGraph::add_fcmp(
  self : EGraph,
  cc : Int,
  left : EClassId,
  right : EClassId,
) -> EClassId {
  self.add({ op: Fcmp(cc), children: [left, right], })
}

///|
/// Add a float promote (f32 -> f64) node
pub fn EGraph::add_fpromote(self : EGraph, operand : EClassId) -> EClassId {
  self.add({ op: Fpromote, children: [operand], })
}

///|
/// Add a float demote (f64 -> f32) node
pub fn EGraph::add_fdemote(self : EGraph, operand : EClassId) -> EClassId {
  self.add({ op: Fdemote, children: [operand], })
}

///|
/// Add a float to signed int conversion node
pub fn EGraph::add_fcvt_to_sint(self : EGraph, operand : EClassId) -> EClassId {
  self.add({ op: FcvtToSint, children: [operand], })
}

///|
/// Add a float to unsigned int conversion node
pub fn EGraph::add_fcvt_to_uint(self : EGraph, operand : EClassId) -> EClassId {
  self.add({ op: FcvtToUint, children: [operand], })
}

///|
/// Add a signed int to float conversion node
pub fn EGraph::add_sint_to_fcvt(self : EGraph, operand : EClassId) -> EClassId {
  self.add({ op: SintToFcvt, children: [operand], })
}

///|
/// Add an unsigned int to float conversion node
pub fn EGraph::add_uint_to_fcvt(self : EGraph, operand : EClassId) -> EClassId {
  self.add({ op: UintToFcvt, children: [operand], })
}

// ============================================================================
// Vector helper constructors
// ============================================================================

///|
/// Add a vector splat node (broadcast scalar to all lanes)
pub fn EGraph::add_splat(self : EGraph, scalar : EClassId) -> EClassId {
  self.add({ op: Splat, children: [scalar], })
}

///|
/// Add a vector constant node
pub fn EGraph::add_vconst(self : EGraph, bits : Bytes) -> EClassId {
  self.add({ op: Vconst(bits), children: [], })
}
