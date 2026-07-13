// IR Optimization Passes
// Implements target-independent optimizations on the high-level IR

///|
/// Result of an optimization pass
pub struct OptResult {
  mut changed : Bool // Whether the IR was modified
} derive(Eq)

///|
fn OptResult::OptResult() -> OptResult {
  { changed: false }
}

///|
/// Mark that the IR was changed
fn OptResult::mark_changed(self : OptResult) -> Unit {
  self.changed = true
}

// ============ Dead Code Elimination ============

///|
/// Dead Code Elimination (DCE)
/// Removes instructions whose results are never used
fn eliminate_dead_code(func : Function) -> OptResult {
  let result = OptResult::OptResult()
  // Build use counts for all values
  let use_counts = compute_use_counts(func)
  // Iterate until fixed point
  let mut changed = true
  while changed {
    changed = false
    for block in func.blocks {
      // Remove dead instructions (iterate backwards to handle chains)
      let mut i = block.instructions.length() - 1
      while i >= 0 {
        let inst = block.instructions[i]
        let all_results_unused = inst.results.length() > 0 &&
          inst.results.all(v => use_counts.get(v.id).unwrap_or(0) == 0)
        if all_results_unused &&
          !inst.opcode.semantics().must_preserve_if_unused() {
          // Remove this instruction
          block.instructions.remove(i) |> ignore
          // Decrement use counts for operands
          for op in inst.operands {
            let count = use_counts.get(op.id).unwrap_or(0)
            if count > 0 {
              use_counts.set(op.id, count - 1)
            }
          }
          changed = true
          result.mark_changed()
        }
        i = i - 1
      }
    }
  }
  result
}

///|
/// Compute use counts for all values in a function
fn compute_use_counts(func : Function) -> @hashmap.HashMap[Int, Int] {
  let counts : @hashmap.HashMap[Int, Int] = HashMap([])
  for block in func.blocks {
    // Count uses in instructions
    for inst in block.instructions {
      for op in inst.operands {
        let count = counts.get(op.id).unwrap_or(0)
        counts.set(op.id, count + 1)
      }
    }
    // Count uses in terminator
    if block.terminator is Some(term) {
      for v in get_terminator_uses(term) {
        let count = counts.get(v.id).unwrap_or(0)
        counts.set(v.id, count + 1)
      }
    }
  }
  counts
}

///|
/// Get values used by a terminator
fn get_terminator_uses(term : Terminator) -> Array[Value] {
  match term {
    Jump(_, args) => args
    Branch(cond, _, true_args, _, false_args) => {
      let values : Array[Value] = [cond]
      for v in true_args {
        values.push(v)
      }
      for v in false_args {
        values.push(v)
      }
      values
    }
    Brz(cond, _, _) | Brnz(cond, _, _) => [cond]
    BrTable(index, _, _) => [index]
    Return(values) => values
    Trap(_) | TrapExit(_) => []
  }
}

// ============ Constant Folding ============

///|
/// Constant Folding
/// Evaluates constant expressions at compile time
fn fold_constants(func : Function) -> OptResult {
  let result = OptResult::OptResult()
  // Map from value id to constant value (if known)
  let constants : @hashmap.HashMap[Int, ConstValue] = HashMap([])
  for block in func.blocks {
    for inst in block.instructions {
      // First, record any constant instruction
      match inst.opcode {
        Scalar(ScalarOp::IntConst(v)) =>
          match inst.first_result() {
            Some(r) =>
              if r.ty is I32 {
                constants.set(r.id, I32(v.to_int()))
              } else {
                constants.set(r.id, I64(v))
              }
            None => ()
          }
        Scalar(ScalarOp::FloatConst32(bits)) =>
          match inst.first_result() {
            Some(r) =>
              constants.set(r.id, F32(Float::reinterpret_from_uint(bits)))
            None => ()
          }
        Scalar(ScalarOp::FloatConst64(bits)) =>
          match inst.first_result() {
            Some(r) => constants.set(r.id, F64(bits.reinterpret_as_double()))
            None => ()
          }
        _ => ()
      }
      // Then try to fold the instruction
      if try_fold_constant(inst, constants) is Some(const_val) &&
        inst.first_result() is Some(v) {
        constants.set(v.id, const_val)
        // Replace instruction with constant
        inst.opcode = const_val.to_opcode()
        // Clear operands since this is now a constant
        inst.operands.clear()
        result.mark_changed()
      }
    }
  }
  result
}

///|
/// Constant value representation
priv enum ConstValue {
  I32(Int)
  I64(Int64)
  F32(Float)
  F64(Double)
}

///|
/// Convert constant value to opcode
fn ConstValue::to_opcode(self : ConstValue) -> Opcode {
  match self {
    I32(v) => Scalar(ScalarOp::IntConst(v.to_int64()))
    I64(v) => Scalar(ScalarOp::IntConst(v))
    F32(v) => Scalar(ScalarOp::FloatConst32(v.reinterpret_as_uint()))
    F64(v) => Scalar(ScalarOp::FloatConst64(v.reinterpret_as_uint64()))
  }
}

///|
/// Try to fold an instruction to a constant
fn try_fold_constant(
  inst : Inst,
  constants : @hashmap.HashMap[Int, ConstValue],
) -> ConstValue? {
  match inst.opcode {
    // Constants are already folded
    Scalar(ScalarOp::IntConst(_))
    | Scalar(ScalarOp::FloatConst32(_))
    | Scalar(ScalarOp::FloatConst64(_)) => None
    // Binary integer operations
    Scalar(ScalarOp::IntBinary(IntBinaryOp::Add)) =>
      fold_binary_int(inst, constants, fn(a, b) { a + b })
    Scalar(ScalarOp::IntBinary(IntBinaryOp::Sub)) =>
      fold_binary_int(inst, constants, fn(a, b) { a - b })
    Scalar(ScalarOp::IntBinary(IntBinaryOp::Mul)) =>
      fold_binary_int(inst, constants, fn(a, b) { a * b })
    Scalar(ScalarOp::IntBinary(IntBinaryOp::SignedDiv)) =>
      fold_sdiv(inst, constants)
    Scalar(ScalarOp::IntBinary(IntBinaryOp::UnsignedDiv)) =>
      fold_udiv(inst, constants)
    // Bitwise operations
    Scalar(ScalarOp::IntBinary(IntBinaryOp::And)) =>
      fold_binary_int(inst, constants, fn(a, b) { a & b })
    Scalar(ScalarOp::IntBinary(IntBinaryOp::Or)) =>
      fold_binary_int(inst, constants, fn(a, b) { a | b })
    Scalar(ScalarOp::IntBinary(IntBinaryOp::Xor)) =>
      fold_binary_int(inst, constants, fn(a, b) { a ^ b })
    Scalar(ScalarOp::IntBinary(IntBinaryOp::ShiftLeft)) =>
      fold_ishl(inst, constants)
    Scalar(ScalarOp::IntBinary(IntBinaryOp::SignedShiftRight)) =>
      fold_sshr(inst, constants)
    Scalar(ScalarOp::IntBinary(IntBinaryOp::UnsignedShiftRight)) =>
      fold_ushr(inst, constants)
    Scalar(ScalarOp::IntBinary(IntBinaryOp::SignedRem)) =>
      fold_srem(inst, constants)
    Scalar(ScalarOp::IntBinary(IntBinaryOp::UnsignedRem)) =>
      fold_urem(inst, constants)
    // Float operations
    Scalar(ScalarOp::FloatBinary(FloatBinaryOp::Add)) =>
      fold_binary_float(inst, constants, fn(a, b) { a + b })
    Scalar(ScalarOp::FloatBinary(FloatBinaryOp::Sub)) =>
      fold_binary_float(inst, constants, fn(a, b) { a - b })
    Scalar(ScalarOp::FloatBinary(FloatBinaryOp::Mul)) =>
      fold_binary_float(inst, constants, fn(a, b) { a * b })
    Scalar(ScalarOp::FloatBinary(FloatBinaryOp::Div)) =>
      fold_binary_float(inst, constants, fn(a, b) { a / b })
    // Comparisons
    Scalar(ScalarOp::IntCompare(cc)) => fold_icmp(inst, constants, cc)
    _ => None
  }
}

///|
/// Get constant value for a value
fn get_const(
  v : Value,
  constants : @hashmap.HashMap[Int, ConstValue],
) -> ConstValue? {
  constants.get(v.id)
}

///|
/// Fold binary integer operation
fn fold_binary_int(
  inst : Inst,
  constants : @hashmap.HashMap[Int, ConstValue],
  op : (Int64, Int64) -> Int64,
) -> ConstValue? {
  if inst.operands.length() != 2 {
    return None
  }
  let a = get_const(inst.operands[0], constants)
  let b = get_const(inst.operands[1], constants)
  match (a, b) {
    (Some(I32(va)), Some(I32(vb))) =>
      Some(I32(op(va.to_int64(), vb.to_int64()).to_int()))
    (Some(I64(va)), Some(I64(vb))) => Some(I64(op(va, vb)))
    _ => None
  }
}

///|
/// Fold binary float operation
fn fold_binary_float(
  inst : Inst,
  constants : @hashmap.HashMap[Int, ConstValue],
  op : (Double, Double) -> Double,
) -> ConstValue? {
  if inst.operands.length() != 2 {
    return None
  }
  let a = get_const(inst.operands[0], constants)
  let b = get_const(inst.operands[1], constants)
  match (a, b) {
    (Some(F32(va)), Some(F32(vb))) =>
      Some(F32(op(va.to_double(), vb.to_double()) |> Float::from_double))
    (Some(F64(va)), Some(F64(vb))) => Some(F64(op(va, vb)))
    _ => None
  }
}

///|
/// Fold integer comparison
fn fold_icmp(
  inst : Inst,
  constants : @hashmap.HashMap[Int, ConstValue],
  cc : IntCC,
) -> ConstValue? {
  if inst.operands.length() != 2 {
    return None
  }
  let a = get_const(inst.operands[0], constants)
  let b = get_const(inst.operands[1], constants)
  match (a, b) {
    (Some(I32(va)), Some(I32(vb))) => {
      let result = eval_icmp_i32(cc, va, vb)
      Some(I32(if result { 1 } else { 0 }))
    }
    (Some(I64(va)), Some(I64(vb))) => {
      let result = eval_icmp_i64(cc, va, vb)
      Some(I32(if result { 1 } else { 0 }))
    }
    _ => None
  }
}

///|
fn fold_ishl(
  inst : Inst,
  constants : @hashmap.HashMap[Int, ConstValue],
) -> ConstValue? {
  if inst.operands.length() != 2 {
    return None
  }
  match
    (
      get_const(inst.operands[0], constants),
      get_const(inst.operands[1], constants),
    ) {
    (Some(I32(a)), Some(I32(b))) => Some(I32(a << (b % 32)))
    (Some(I64(a)), Some(I64(b))) => Some(I64(a << (b.to_int() % 64)))
    _ => None
  }
}

///|
fn fold_sshr(
  inst : Inst,
  constants : @hashmap.HashMap[Int, ConstValue],
) -> ConstValue? {
  if inst.operands.length() != 2 {
    return None
  }
  match
    (
      get_const(inst.operands[0], constants),
      get_const(inst.operands[1], constants),
    ) {
    (Some(I32(a)), Some(I32(b))) => Some(I32(a >> (b % 32)))
    (Some(I64(a)), Some(I64(b))) => Some(I64(a >> (b.to_int() % 64)))
    _ => None
  }
}

///|
fn fold_ushr(
  inst : Inst,
  constants : @hashmap.HashMap[Int, ConstValue],
) -> ConstValue? {
  if inst.operands.length() != 2 {
    return None
  }
  match
    (
      get_const(inst.operands[0], constants),
      get_const(inst.operands[1], constants),
    ) {
    (Some(I32(a)), Some(I32(b))) => {
      let shift = b % 32
      let result = (a.reinterpret_as_uint() >> shift)
        |> UInt::reinterpret_as_int
      Some(I32(result))
    }
    (Some(I64(a)), Some(I64(b))) => {
      let shift = b.to_int() % 64
      let result = (a.reinterpret_as_uint64() >> shift).reinterpret_as_int64()
      Some(I64(result))
    }
    _ => None
  }
}

///|
fn fold_sdiv(
  inst : Inst,
  constants : @hashmap.HashMap[Int, ConstValue],
) -> ConstValue? {
  if inst.operands.length() != 2 {
    return None
  }
  match
    (
      get_const(inst.operands[0], constants),
      get_const(inst.operands[1], constants),
    ) {
    (Some(I32(a)), Some(I32(b))) =>
      if b == 0 {
        None
      } else if a == -2147483648 && b == -1 {
        None
      } else {
        Some(I32(a / b))
      }
    (Some(I64(a)), Some(I64(b))) =>
      if b == 0L {
        None
      } else if a == -9223372036854775808L && b == -1L {
        None
      } else {
        Some(I64(a / b))
      }
    _ => None
  }
}

///|
fn fold_udiv(
  inst : Inst,
  constants : @hashmap.HashMap[Int, ConstValue],
) -> ConstValue? {
  if inst.operands.length() != 2 {
    return None
  }
  match
    (
      get_const(inst.operands[0], constants),
      get_const(inst.operands[1], constants),
    ) {
    (Some(I32(a)), Some(I32(b))) =>
      if b == 0 {
        None
      } else {
        let result = (a.reinterpret_as_uint() / b.reinterpret_as_uint())
          |> UInt::reinterpret_as_int
        Some(I32(result))
      }
    (Some(I64(a)), Some(I64(b))) =>
      if b == 0L {
        None
      } else {
        let result = (a.reinterpret_as_uint64() / b.reinterpret_as_uint64())
          |> UInt64::reinterpret_as_int64
        Some(I64(result))
      }
    _ => None
  }
}

///|
fn fold_srem(
  inst : Inst,
  constants : @hashmap.HashMap[Int, ConstValue],
) -> ConstValue? {
  if inst.operands.length() != 2 {
    return None
  }
  match
    (
      get_const(inst.operands[0], constants),
      get_const(inst.operands[1], constants),
    ) {
    (Some(I32(a)), Some(I32(b))) => if b == 0 { None } else { Some(I32(a % b)) }
    (Some(I64(a)), Some(I64(b))) =>
      if b == 0L {
        None
      } else {
        Some(I64(a % b))
      }
    _ => None
  }
}

///|
fn fold_urem(
  inst : Inst,
  constants : @hashmap.HashMap[Int, ConstValue],
) -> ConstValue? {
  if inst.operands.length() != 2 {
    return None
  }
  match
    (
      get_const(inst.operands[0], constants),
      get_const(inst.operands[1], constants),
    ) {
    (Some(I32(a)), Some(I32(b))) =>
      if b == 0 {
        None
      } else {
        let result = (a.reinterpret_as_uint() % b.reinterpret_as_uint())
          |> UInt::reinterpret_as_int
        Some(I32(result))
      }
    (Some(I64(a)), Some(I64(b))) =>
      if b == 0L {
        None
      } else {
        let result = (a.reinterpret_as_uint64() % b.reinterpret_as_uint64())
          |> UInt64::reinterpret_as_int64
        Some(I64(result))
      }
    _ => None
  }
}

///|
/// Evaluate i32 comparison
fn eval_icmp_i32(cc : IntCC, a : Int, b : Int) -> Bool {
  match cc {
    Eq => a == b
    Ne => a != b
    Slt => a < b
    Sle => a <= b
    Sgt => a > b
    Sge => a >= b
    Ult => a.reinterpret_as_uint() < b.reinterpret_as_uint()
    Ule => a.reinterpret_as_uint() <= b.reinterpret_as_uint()
    Ugt => a.reinterpret_as_uint() > b.reinterpret_as_uint()
    Uge => a.reinterpret_as_uint() >= b.reinterpret_as_uint()
  }
}

///|
/// Evaluate i64 comparison
fn eval_icmp_i64(cc : IntCC, a : Int64, b : Int64) -> Bool {
  match cc {
    Eq => a == b
    Ne => a != b
    Slt => a < b
    Sle => a <= b
    Sgt => a > b
    Sge => a >= b
    Ult => a.reinterpret_as_uint64() < b.reinterpret_as_uint64()
    Ule => a.reinterpret_as_uint64() <= b.reinterpret_as_uint64()
    Ugt => a.reinterpret_as_uint64() > b.reinterpret_as_uint64()
    Uge => a.reinterpret_as_uint64() >= b.reinterpret_as_uint64()
  }
}

// ============ Copy Propagation ============

///|
/// Alias/copy canonicalization pass.
/// Resolves visible copy chains along the dominator tree and rewrites operands
/// to canonical values (Cranelift analogue: `resolve_all_aliases()`).
fn canonicalize_aliases(func : Function) -> OptResult {
  let result = OptResult::OptResult()
  if func.blocks.length() == 0 {
    return result
  }
  // Build CFG and compute dominators.
  let cfg = CFG::build(func)
  let idom = cfg.compute_dominators()
  let domtree = build_dominator_tree(idom)
  // Build block_id -> array_index mapping.
  let block_idx : @hashmap.HashMap[Int, Int] = HashMap([])
  for i, block in func.blocks {
    block_idx.set(block.id, i)
  }
  // Active alias environment for the current dominator-tree path.
  let aliases : @hashmap.HashMap[Int, Value] = HashMap([])
  fn dfs(block_id : Int) {
    let idx = block_idx.get(block_id).unwrap()
    let block = func.blocks[idx]
    // Track aliases introduced in this block so we can pop on exit.
    let local_aliases : Array[Int] = []
    for inst in block.instructions {
      // Canonicalize operands through currently visible alias chain.
      for i, op in inst.operands {
        if resolve_copy(op, aliases) is Some(resolved) && resolved.id != op.id {
          inst.operands[i] = resolved
          result.mark_changed()
        }
      }
      // If this instruction defines a copy, make its destination an alias.
      if inst.opcode is Scalar(ScalarOp::Copy) &&
        inst.first_result() is Some(dest) &&
        inst.operands.length() > 0 {
        aliases.set(dest.id, inst.operands[0])
        local_aliases.push(dest.id)
      }
    }
    // Canonicalize terminator operands as well.
    if block.terminator is Some(term) {
      let new_term = propagate_copies_in_terminator(term, aliases, result)
      block.terminator = Some(new_term)
    }
    // Recurse into dominated children.
    if block_id < domtree.length() {
      for child in domtree[block_id] {
        dfs(child)
      }
    }
    // Pop this block's aliases.
    for id in local_aliases {
      aliases.remove(id)
    }
  }

  // Start DFS from entry block (block 0).
  if cfg.is_valid(0) {
    dfs(0)
  }
  result
}

///|
/// Resolve a value through copy chain
fn resolve_copy(v : Value, copies : @hashmap.HashMap[Int, Value]) -> Value? {
  // Follow copy chain (with cycle detection)
  let mut current = v
  let visited : @hashmap.HashMap[Int, Bool] = HashMap([])
  while true {
    if visited.get(current.id).unwrap_or(false) {
      break // Cycle detected
    }
    visited.set(current.id, true)
    match copies.get(current.id) {
      Some(source) => current = source
      None => break
    }
  }
  Some(current)
}

///|
/// Propagate copies in terminator
fn propagate_copies_in_terminator(
  term : Terminator,
  copies : @hashmap.HashMap[Int, Value],
  result : OptResult,
) -> Terminator {
  match term {
    Jump(target, args) => {
      let new_args : Array[Value] = []
      for arg in args {
        match resolve_copy(arg, copies) {
          Some(resolved) => {
            if resolved.id != arg.id {
              result.mark_changed()
            }
            new_args.push(resolved)
          }
          None => new_args.push(arg)
        }
      }
      Jump(target, new_args)
    }
    Brz(cond, then_t, else_t) =>
      match resolve_copy(cond, copies) {
        Some(resolved) => {
          if resolved.id != cond.id {
            result.mark_changed()
          }
          Brz(resolved, then_t, else_t)
        }
        None => term
      }
    Brnz(cond, then_t, else_t) =>
      match resolve_copy(cond, copies) {
        Some(resolved) => {
          if resolved.id != cond.id {
            result.mark_changed()
          }
          Brnz(resolved, then_t, else_t)
        }
        None => term
      }
    Branch(cond, true_t, true_args, false_t, false_args) => {
      let new_cond = match resolve_copy(cond, copies) {
        Some(resolved) => {
          if resolved.id != cond.id {
            result.mark_changed()
          }
          resolved
        }
        None => cond
      }
      let new_true_args : Array[Value] = []
      for arg in true_args {
        match resolve_copy(arg, copies) {
          Some(resolved) => {
            if resolved.id != arg.id {
              result.mark_changed()
            }
            new_true_args.push(resolved)
          }
          None => new_true_args.push(arg)
        }
      }
      let new_false_args : Array[Value] = []
      for arg in false_args {
        match resolve_copy(arg, copies) {
          Some(resolved) => {
            if resolved.id != arg.id {
              result.mark_changed()
            }
            new_false_args.push(resolved)
          }
          None => new_false_args.push(arg)
        }
      }
      Branch(new_cond, true_t, new_true_args, false_t, new_false_args)
    }
    BrTable(index, targets, default_t) =>
      match resolve_copy(index, copies) {
        Some(resolved) => {
          if resolved.id != index.id {
            result.mark_changed()
          }
          BrTable(resolved, targets, default_t)
        }
        None => term
      }
    Return(values) => {
      let new_values : Array[Value] = []
      for v in values {
        match resolve_copy(v, copies) {
          Some(resolved) => {
            if resolved.id != v.id {
              result.mark_changed()
            }
            new_values.push(resolved)
          }
          None => new_values.push(v)
        }
      }
      Return(new_values)
    }
    Trap(_) | TrapExit(_) => term
  }
}
