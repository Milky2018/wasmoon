///|
fn OptimizerSession::wide_parts(
  self : OptimizerSession,
  value : @milkir.Value,
  operation : @milkir.IntBinaryOp,
) -> (@milkir.Value, @milkir.Value)? {
  guard value.ty == I64 &&
    self.definition(value) is Some(inst) &&
    inst.opcode is Scalar(IntBinary(actual)) &&
    actual == operation &&
    inst.operands is [left, right] else {
    return None
  }
  Some((left, right))
}

///|
fn OptimizerSession::wide_shift(
  self : OptimizerSession,
  value : @milkir.Value,
  operation : @milkir.IntBinaryOp,
) -> @milkir.Value? {
  guard self.wide_parts(value, operation) is Some((source, amount)) &&
    self.int_constant(amount) == Some(32L) else {
    return None
  }
  Some(source)
}

///|
fn OptimizerSession::wide_limb(
  self : OptimizerSession,
  value : @milkir.Value,
  high : Bool,
) -> @milkir.Value? {
  if high {
    return self.wide_shift(value, UnsignedShiftRight)
  }
  guard self.wide_parts(value, And) is Some((left, right)) else { return None }
  if self.int_constant(right) == Some(0xFFFFFFFFL) {
    Some(left)
  } else if self.int_constant(left) == Some(0xFFFFFFFFL) {
    Some(right)
  } else {
    None
  }
}

///|
fn OptimizerSession::wide_limb_product(
  self : OptimizerSession,
  value : @milkir.Value,
  a : @milkir.Value,
  b : @milkir.Value,
  a_high : Bool,
  b_high : Bool,
) -> Bool {
  guard self.wide_parts(value, Mul) is Some((left, right)) else { return false }
  for order in 0..<2 {
    let x_value = if order == 0 { left } else { right }
    let y_value = if order == 0 { right } else { left }
    if self.wide_limb(x_value, a_high) is Some(x) &&
      self.wide_limb(y_value, b_high) is Some(y) &&
      self.same_value(x, a) &&
      self.same_value(y, b) {
      return true
    }
  }
  false
}

///|
/// Recognize the carry-preserving 32-bit decomposition, without following
/// arbitrary expression trees: lo=al*bl, carry=bl*ah+(lo>>32),
/// middle=bh*al+(carry&mask). All products and sums fit in unsigned 64 bits.
fn OptimizerSession::wide_middle(
  self : OptimizerSession,
  value : @milkir.Value,
) -> (@milkir.Value, @milkir.Value, @milkir.Value, @milkir.Value)? {
  guard self.wide_parts(value, Add) is Some((left, right)) else { return None }
  for order in 0..<2 {
    let cross = if order == 0 { left } else { right }
    let masked = if order == 0 { right } else { left }
    guard self.wide_limb(masked, false) is Some(carry) &&
      self.wide_parts(cross, Mul) is Some((x, y)) &&
      self.wide_parts(carry, Add) is Some((u, v)) else {
      continue
    }
    for order in 0..<2 {
      let high = if order == 0 { x } else { y }
      let low = if order == 0 { y } else { x }
      guard self.wide_limb(high, true) is Some(b) &&
        self.wide_limb(low, false) is Some(a) else {
        continue
      }
      for order in 0..<2 {
        let product = if order == 0 { u } else { v }
        let shifted = if order == 0 { v } else { u }
        if self.wide_shift(shifted, UnsignedShiftRight) is Some(lo) &&
          self.wide_limb_product(lo, a, b, false, false) &&
          self.wide_limb_product(product, a, b, true, false) {
          return Some((a, b, lo, carry))
        }
      }
    }
  }
  None
}

///|
/// Collapse only the exact unsigned full-width product. The two observable
/// halves can be used independently; ordinary DCE removes only unused limbs.
/// Matching is constant-depth and never rewrites a partial/near-miss product.
fn OptimizerSession::rewrite_wide_multiply(
  self : OptimizerSession,
  inst : @milkir.Inst,
  operation : @milkir.IntBinaryOp,
) -> Bool {
  guard operation is (Add | Or) &&
    inst.first_result() is Some(result) &&
    result.ty == I64 &&
    inst.operands is [left, right] else {
    return false
  }
  for order in 0..<2 {
    let rest = if order == 0 { left } else { right }
    let shifted = if order == 0 { right } else { left }
    guard self.wide_shift(
        shifted,
        if operation == Add {
          UnsignedShiftRight
        } else {
          ShiftLeft
        },
      )
      is Some(middle) &&
      self.wide_middle(middle) is Some((a, b, low, carry)) else {
      continue
    }
    if operation == Or {
      if self.wide_limb(rest, false) is Some(value) &&
        self.same_value(value, low) {
        return self.replace_binary(inst, Mul, a, b)
      }
    } else {
      guard self.wide_parts(rest, Add) is Some((u, v)) else { continue }
      for order in 0..<2 {
        let product = if order == 0 { u } else { v }
        let shifted = if order == 0 { v } else { u }
        if self.wide_shift(shifted, UnsignedShiftRight) is Some(value) &&
          self.same_value(value, carry) &&
          self.wide_limb_product(product, a, b, true, true) {
          return self.replace_binary(inst, UnsignedMulHigh, a, b)
        }
      }
    }
  }
  false
}
